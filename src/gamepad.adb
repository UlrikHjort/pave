-- ***************************************************************************
--                      PAVÉ - Gamepad
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

with Interfaces;           use Interfaces;
with Interfaces.C;         use Interfaces.C;
with Interfaces.C.Strings;
with System;
with Ada.Text_IO;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Characters.Handling;
with GNAT.OS_Lib;
with Ada.Numerics.Elementary_Functions;

package body Gamepad is

   ------------------------------------------------------------------ libc
   function C_Open (Path : Interfaces.C.Strings.chars_ptr; Flags : int) return int;
   pragma Import (C, C_Open, "open");
   function C_Read (FD : int; Buf : System.Address; N : size_t) return long;
   pragma Import (C, C_Read, "read");
   function C_Close (FD : int) return int;
   pragma Import (C, C_Close, "close");

   O_RDONLY   : constant int := 0;
   O_NONBLOCK : constant int := 8#4000#;
   EAGAIN     : constant := 11;

   type JS_Event is record
      Time   : Unsigned_32;
      Value  : Integer_16;
      Kind   : Unsigned_8;
      Number : Unsigned_8;
   end record;
   pragma Convention (C, JS_Event);

   JS_BUTTON : constant Unsigned_8 := 16#01#;
   JS_AXIS   : constant Unsigned_8 := 16#02#;

   FD      : int := -1;
   Retry_T : Float := 0.0;
   Raw     : array (0 .. 7) of Float := (2 => -1.0, 5 => -1.0, others => 0.0);

   ------------------------------------------------------------------ device choice
   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   function Device_Name (N : Natural) return String is
      F    : Ada.Text_IO.File_Type;
      Path : constant String := "/sys/class/input/js" & Img (N) & "/device/name";
   begin
      if not Ada.Directories.Exists (Path) then
         return "";
      end if;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      declare
         S : constant String := Ada.Text_IO.Get_Line (F);
      begin
         Ada.Text_IO.Close (F);
         return Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
      end;
   exception
      when others =>
         return "";
   end Device_Name;

   function Score (Dev_Name : String) return Integer is
      L : constant String := Ada.Characters.Handling.To_Lower (Dev_Name);
      function Has (S : String) return Boolean is (Ada.Strings.Fixed.Index (L, S) > 0);
   begin
      if Dev_Name = "" then
         return -1;
      elsif Has ("x-box") or else Has ("xbox") or else Has ("x box") or else Has ("xinput") then
         return 3;
      elsif Has ("wheel") then
         return 0;      --  racing wheels are a poor fit for this mapping
      elsif Has ("pad") or else Has ("controller") then
         return 2;
      else
         return 1;
      end if;
   end Score;

   procedure Try_Open is
      Path   : Unbounded_String;
      Best_S : Integer := 0;
   begin
      if Ada.Environment_Variables.Exists ("PAVE_JOYSTICK") then
         Path := To_Unbounded_String (Ada.Environment_Variables.Value ("PAVE_JOYSTICK"));
         Name := Path;
      else
         for N in 0 .. 15 loop
            declare
               DN : constant String := Device_Name (N);
               S  : constant Integer := Score (DN);
            begin
               if S > Best_S then
                  Best_S := S;
                  Path := To_Unbounded_String ("/dev/input/js" & Img (N));
                  Name := To_Unbounded_String (DN);
               end if;
            end;
         end loop;
      end if;
      if Length (Path) = 0 then
         return;
      end if;
      declare
         P : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (To_String (Path));
      begin
         FD := C_Open (P, O_RDONLY + O_NONBLOCK);
         Interfaces.C.Strings.Free (P);
      end;
      if FD >= 0 then
         Connected := True;
         Changed := True;
         Raw := (2 => -1.0, 5 => -1.0, others => 0.0);
         Down := (others => False);
      end if;
   end Try_Open;

   procedure Disconnect is
      R : int;
      pragma Unreferenced (R);
   begin
      R := C_Close (FD);
      FD := -1;
      Connected := False;
      Changed := True;
      Down := (others => False);
      LX := 0.0; LY := 0.0; RX := 0.0; RY := 0.0; LT := 0.0; RT := 0.0;
   end Disconnect;

   ------------------------------------------------------------------ processing
   procedure Set (B : Button; V : Boolean) is
   begin
      if V and then not Down (B) then
         Hit (B) := True;
      end if;
      Down (B) := V;
   end Set;

   --  radial deadzone, rescaled so movement starts smoothly at the edge
   procedure Stick (AX, AY : Float; OX, OY : out Float) is
      Dead : constant Float := 0.22;
      M    : constant Float := Float'Min (1.0, Ada.Numerics.Elementary_Functions.Sqrt (AX * AX + AY * AY));
   begin
      if M < Dead then
         OX := 0.0; OY := 0.0;
      else
         declare
            K : constant Float := (M - Dead) / (1.0 - Dead) / M;
         begin
            OX := Float'Max (-1.0, Float'Min (1.0, AX * K));
            OY := Float'Max (-1.0, Float'Min (1.0, AY * K));
         end;
      end if;
   end Stick;

   procedure Handle (E : JS_Event) is
      K : constant Unsigned_8 := E.Kind and 16#7F#;   --  strip JS_EVENT_INIT
      N : constant Natural := Natural (E.Number);
      V : constant Float := Float (E.Value) / 32_767.0;
   begin
      if K = JS_BUTTON then
         case N is
            when 0  => Set (A, E.Value /= 0);
            when 1  => Set (B, E.Value /= 0);
            when 2  => Set (X, E.Value /= 0);
            when 3  => Set (Y, E.Value /= 0);
            when 4  => Set (LB, E.Value /= 0);
            when 5  => Set (RB, E.Value /= 0);
            when 6  => Set (Back, E.Value /= 0);
            when 7  => Set (Start, E.Value /= 0);
            when 8  => Set (Guide, E.Value /= 0);
            when 9  => Set (LS, E.Value /= 0);
            when 10 => Set (RS, E.Value /= 0);
            when others => null;
         end case;
      elsif K = JS_AXIS and then N <= Raw'Last then
         Raw (N) := V;
         case N is
            when 6 => Set (D_Left, V < -0.5); Set (D_Right, V > 0.5);
            when 7 => Set (D_Up, V < -0.5); Set (D_Down, V > 0.5);
            when others => null;
         end case;
      end if;
   end Handle;

   procedure Poll (DT : Float) is
      E : JS_Event;
      R : long;
   begin
      if FD < 0 then
         Retry_T := Retry_T - DT;
         if Retry_T <= 0.0 then
            Retry_T := 2.0;
            Try_Open;
         end if;
         if FD < 0 then
            return;
         end if;
      end if;
      loop
         R := C_Read (FD, E'Address, 8);
         if R = 8 then
            Handle (E);
         else
            if R < 0 and then GNAT.OS_Lib.Errno /= EAGAIN then
               Disconnect;     --  unplugged
               return;
            end if;
            exit;
         end if;
      end loop;
      Stick (Raw (0), Raw (1), LX, LY);
      Stick (Raw (3), Raw (4), RX, RY);
      LT := Float'Max (0.0, (Raw (2) + 1.0) / 2.0);   --  triggers rest at -1
      RT := Float'Max (0.0, (Raw (5) + 1.0) / 2.0);
      if LT < 0.05 then
         LT := 0.0;
      end if;
      if RT < 0.05 then
         RT := 0.0;
      end if;
   end Poll;

   procedure End_Frame is
   begin
      Hit := (others => False);
   end End_Frame;

end Gamepad;
