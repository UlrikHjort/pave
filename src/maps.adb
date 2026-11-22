-- ***************************************************************************
--                      PAVÉ - Maps
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************

with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;
with Ada.Strings.Fixed;
with GNAT.OS_Lib;
with Interfaces.C;
with System;

package body Maps is

   use GNAT.OS_Lib;

   Pid     : Process_Id := Invalid_Pid;
   Poll_T  : Float := 0.0;

   ------------------------------------------------------------------ locations
   --  the folder holding data/ and tools/: the current directory or next to the program
   function Root return String is
      Exe : constant String := Ada.Directories.Containing_Directory (Ada.Command_Line.Command_Name);
      function Has (C : String) return Boolean is
        (Ada.Directories.Exists (C & "/tools/get_map.py") or else Ada.Directories.Exists (C & "/data"));
   begin
      if Has (".") then
         return ".";
      elsif Has (Exe) then
         return Exe;
      elsif Has (Exe & "/..") then
         return Exe & "/..";
      end if;
      return ".";
   exception
      when others => return ".";
   end Root;

   function Key (W : World_Id) return String is
     (case W is when Small => "small", when Large => "large", when Copenhagen => "copenhagen");

   function File (W : World_Id) return String is
     (case W is when Small => "paris-small", when Large => "paris-large", when Copenhagen => "copenhagen");

   function Path (W : World_Id) return String is (Root & "/data/" & File (W) & ".bin");

   function Installed (W : World_Id) return Boolean is (Ada.Directories.Exists (Path (W)));

   function Any_Installed return Boolean is
     (for some W in World_Id => Installed (W));

   function Title (W : World_Id) return String is
     (case W is when Small => "Central Paris", when Large => "All of Paris", when Copenhagen => "Copenhagen");

   function About (W : World_Id) return String is
     (case W is
         when Small      => "Saint-Germain, Ile de la Cite, the Louvre, the Marais",
         when Large      => "Every street inside the Boulevard Peripherique",
         when Copenhagen => "Indre By, Nyhavn, Christianshavn, Vesterbro, Norrebro");

   function Download_Info (W : World_Id) return String is
     (case W is
         when Small      => "2.6 x 2.2 km  -  20 MB, a few minutes",
         when Large      => "12.6 x 9.9 km  -  350-500 MB, 10-60 minutes",
         when Copenhagen => "6.0 x 5.6 km  -  about 500 MB, 10-20 minutes");

   ------------------------------------------------------------------ preference
   function Pref_File return String is (Root & "/data/world.txt");

   function Progress_Path return String is (Root & "/data/progress-" & Key (Current) & ".txt");

   procedure Remember (W : World_Id) is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Pref_File);
      Ada.Text_IO.Put_Line (F, Key (W));
      Ada.Text_IO.Close (F);
   exception
      when others => null;
   end Remember;

   procedure Choose_Startup is
      Pref : World_Id := Small;
      F    : Ada.Text_IO.File_Type;
   begin
      begin
         Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Pref_File);
         declare
            L : constant String := Ada.Text_IO.Get_Line (F);
         begin
            for W in World_Id loop
               if Key (W) = L then
                  Pref := W;
               end if;
            end loop;
         end;
         Ada.Text_IO.Close (F);
      exception
         when others => null;
      end;
      if not Installed (Pref) then
         for W in World_Id loop
            if Installed (W) then
               Pref := W;
               exit;
            end if;
         end loop;
      end if;
      Selected := Pref;
      Current := Pref;
   end Choose_Startup;

   ------------------------------------------------------------------ installer
   function Python return String is
      P : GNAT.OS_Lib.String_Access := Locate_Exec_On_Path ("python3");
   begin
      if P = null then
         return "";
      end if;
      declare
         S : constant String := P.all;
      begin
         Free (P);
         return S;
      end;
   end Python;

   function Can_Install return Boolean is
     (Python /= "" and then Ada.Directories.Exists (Root & "/tools/get_map.py"));

   function Installing return Boolean is (Pid /= Invalid_Pid);

   function Status_File (W : World_Id) return String is
     (Root & "/data/raw/" & Key (W) & "/status.txt");

   procedure Read_Status is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Status_File (Install_World));
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L  : constant String := Ada.Text_IO.Get_Line (F);
            Eq : constant Natural := Ada.Strings.Fixed.Index (L, "=");
         begin
            if Eq > 0 then
               declare
                  K : constant String := L (L'First .. Eq - 1);
                  V : constant String := L (Eq + 1 .. L'Last);
               begin
                  if K = "stage" then
                     Stage := To_Unbounded_String (V);
                  elsif K = "done" then
                     Done := Natural'Value (V);
                  elsif K = "total" then
                     Total := Natural'Value (V);
                  elsif K = "unit" then
                     Unit := To_Unbounded_String (V);
                  elsif K = "message" then
                     Message := To_Unbounded_String (V);
                  end if;
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Read_Status;

   procedure Start_Install (W : World_Id) is
      Py : constant String := Python;
   begin
      if Installing then
         return;
      end if;
      Install_World := W;
      Failed := False;
      Stage := To_Unbounded_String ("download");
      Done := 0; Total := 0;
      Message := To_Unbounded_String ("Contacting the OpenStreetMap servers...");
      if Py = "" then
         Failed := True;
         Stage := To_Unbounded_String ("error");
         Message := To_Unbounded_String ("python3 was not found - install it, or run tools/get_map.py yourself");
         return;
      end if;
      declare
         Args : Argument_List :=
           (new String'(Root & "/tools/get_map.py"), new String'(Key (W)), new String'("--quiet"));
      begin
         Pid := Non_Blocking_Spawn (Py, Args);
         for A of Args loop
            Free (A);
         end loop;
      end;
      if Pid = Invalid_Pid then
         Failed := True;
         Stage := To_Unbounded_String ("error");
         Message := To_Unbounded_String ("could not start tools/get_map.py");
      end if;
   end Start_Install;

   --  waitpid (pid, NULL, WNOHANG): pid when the child has exited, 0 while it runs
   function Waitpid (P : Interfaces.C.int; Status : System.Address; Options : Interfaces.C.int)
                     return Interfaces.C.int;
   pragma Import (C, Waitpid, "waitpid");
   WNOHANG : constant := 1;

   function Child_Exited return Boolean is
      use type Interfaces.C.int;
      R : constant Interfaces.C.int :=
        Waitpid (Interfaces.C.int (Pid_To_Integer (Pid)), System.Null_Address, WNOHANG);
   begin
      return R /= 0;
   end Child_Exited;

   procedure Poll (DT : Float) is
   begin
      if not Installing then
         return;
      end if;
      Poll_T := Poll_T - DT;
      if Poll_T > 0.0 then
         return;
      end if;
      Poll_T := 0.5;
      Read_Status;
      if Child_Exited then
         Pid := Invalid_Pid;
         Read_Status;
         if To_String (Stage) = "done" and then Installed (Install_World) then
            Just_Finished := True;
         else
            Failed := True;
            if To_String (Stage) /= "error" then
               Stage := To_Unbounded_String ("error");
               Message := To_Unbounded_String ("the installer stopped unexpectedly - see data/raw/"
                                               & Key (Install_World) & "/build.log");
            end if;
         end if;
      end if;
   end Poll;

   procedure Cancel_Install is
   begin
      if Installing then
         Kill (Pid, Hard_Kill => True);    --  SIGINT/SIGTERM may be blocked (inherited signal mask)
         declare
            R : constant Interfaces.C.int :=
              Waitpid (Interfaces.C.int (Pid_To_Integer (Pid)), System.Null_Address, 0);   --  reap it
            pragma Unreferenced (R);
         begin
            null;
         end;
         Pid := Invalid_Pid;
         Stage := To_Unbounded_String ("cancelled");
         Message := To_Unbounded_String ("Download paused - choose the world again to resume.");
      end if;
   end Cancel_Install;

   procedure Stop is
   begin
      Cancel_Install;
   end Stop;

end Maps;
