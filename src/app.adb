-- ***************************************************************************
--                      PAVÉ - App
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

with Ada.Command_Line;    use Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Text_IO;         use Ada.Text_IO;
with Ada.Calendar;        use type Ada.Calendar.Time;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Glib;                use Glib;
with Gdk.Event;           use Gdk.Event;
with Gdk.Frame_Clock;     use Gdk.Frame_Clock;
with Gtk.Main;
with Gtk.Window;          use Gtk.Window;
with Gtk.Drawing_Area;    use Gtk.Drawing_Area;
with Gtk.Widget;          use Gtk.Widget;
with Gtk.Enums;
with Cairo;               use Cairo;
with Cairo.Image_Surface; use Cairo.Image_Surface;
with Cairo.Png;
with Cairo.Surface;
with Util;                use Util;
with State;               use State;
with World;
with World_Render;
with Game;
with Render;
with Input;
with Physics;
with Gamepad;
with Sound;
with Maps;
with Secrets;
use type Sound.Effect;

package body App is

   Win       : Gtk_Window;
   Area      : Gtk_Drawing_Area;
   Last_Time : Gint64 := 0;

   ------------------------------------------------------------------ data file
   --  PAVE_MAP=file overrides the installed worlds (handy for testing)
   Map_Override : Unbounded_String;     --  set by --capture for a scene in another world

   function Map_Path return String is
     (if Length (Map_Override) > 0 then To_String (Map_Override)
      elsif Ada.Environment_Variables.Exists ("PAVE_MAP") then Ada.Environment_Variables.Value ("PAVE_MAP")
      else Maps.Path (Maps.Current));

   function Have_Map return Boolean is
     (Ada.Environment_Variables.Exists ("PAVE_MAP") or else Maps.Installed (Maps.Current));

   procedure Load_All is
      T0 : constant Ada.Calendar.Time := Ada.Calendar.Clock;
   begin
      World.Load (Map_Path);
      World_Render.Init;
      Game.Init;
      Maps.Loaded := True;
      Put_Line ((if Ada.Environment_Variables.Exists ("PAVE_MAP") then Map_Path else Maps.Title (Maps.Current))
                & " loaded in" & Duration'Image (Ada.Calendar.Clock - T0) & " s");
   end Load_All;

   ------------------------------------------------------------------ choosing / installing worlds
   Pending_Frames : Natural := 0;       --  frames to show the loading screen before loading
   Play_After     : Boolean := False;   --  go straight into the game after loading

   procedure Request_Load (W : Maps.World_Id; Play : Boolean) is
   begin
      Maps.Selected := W;
      Maps.Loading := True;
      Pending_Frames := 2;
      Play_After := Play;
   end Request_Load;

   procedure Finish_Load is
   begin
      Maps.Current := Maps.Selected;
      Maps.Remember (Maps.Current);
      Load_All;
      Maps.Loading := False;
      if Play_After then
         Game.Start_Game;
      end if;
      Last_Time := 0;   --  don't count the loading time as one huge frame
   end Finish_Load;

   function Confirm return Boolean is
     (Input.Hit (Input.K_Enter) or else Input.Hit (Input.K_Space) or else Input.Mouse_Clicked
      or else Gamepad.Hit (Gamepad.A) or else Gamepad.Hit (Gamepad.Start));

   procedure Consume_Confirm is
   begin
      Input.Hit (Input.K_Enter) := False; Input.Hit (Input.K_Space) := False;
      Input.Mouse_Clicked := False; Input.Mouse_Down := False;
      Gamepad.Hit (Gamepad.A) := False; Gamepad.Hit (Gamepad.Start) := False;
   end Consume_Confirm;

   procedure Choose_Input is
      use Maps;
   begin
      if Input.Hit (Input.K_Left) or else Input.Hit (Input.K_Right) or else Input.Hit (Input.K_Up)
        or else Input.Hit (Input.K_Down) or else Gamepad.Hit (Gamepad.D_Left) or else Gamepad.Hit (Gamepad.D_Right)
      then
         declare
            Back : constant Boolean := Input.Hit (Input.K_Left) or else Input.Hit (Input.K_Up)
              or else Gamepad.Hit (Gamepad.D_Left);
         begin
            Selected := (if Back then (if Selected = World_Id'First then World_Id'Last else World_Id'Pred (Selected))
                         else (if Selected = World_Id'Last then World_Id'First else World_Id'Succ (Selected)));
         end;
      end if;
      if Input.Hit (Input.K_1) then
         Selected := Small;
      elsif Input.Hit (Input.K_2) then
         Selected := Large;
      elsif Input.Hit (Input.K_3) then
         Selected := Copenhagen;
      end if;
      if (Input.Hit (Input.K_Esc) or else Gamepad.Hit (Gamepad.B)) and then Installing then
         Cancel_Install;
      end if;
   end Choose_Input;

   --  no world loaded yet: the download menu
   procedure Setup_Frame (DT : Float) is
      use Maps;
   begin
      State.Time := State.Time + DT;
      Choose_Input;
      if Confirm then
         if Installed (Selected) then
            Request_Load (Selected, Play => False);
         elsif not Installing then
            Start_Install (Selected);
         end if;
      end if;
      Input.End_Frame;
      Gamepad.End_Frame;
   end Setup_Frame;

   --  title screen of a loaded world: Left / Right picks another world
   procedure Title_Input is
      use Maps;
   begin
      Choose_Input;
      if Selected /= Current and then Confirm then
         Consume_Confirm;
         if Installed (Selected) then
            Request_Load (Selected, Play => True);
         elsif not Installing then
            Start_Install (Selected);
         end if;
      end if;
   end Title_Input;

   procedure Install_Events is
      use Maps;
   begin
      if Just_Finished then
         Just_Finished := False;
         if not Loaded then
            Request_Load (Install_World, Play => False);
         else
            State.Message := To_Unbounded_String
              (Title (Install_World) & " is installed - pick it on the title screen (pause, then Enter)");
            State.Msg_T := 8.0;
         end if;
      end if;
   end Install_Events;

   ------------------------------------------------------------------ GTK callbacks
   function On_Draw (Self : access Gtk_Widget_Record'Class; Cr : Cairo_Context) return Boolean is
   begin
      Screen_W := Float (Self.Get_Allocated_Width);
      Screen_H := Float (Self.Get_Allocated_Height);
      if Maps.Loaded and then not Maps.Loading then
         Render.Draw (Cr);
      else
         Render.Draw_Setup (Cr);
      end if;
      return True;
   end On_Draw;

   function On_Tick (W     : not null access Gtk_Widget_Record'Class;
                     Clock : not null access Gdk_Frame_Clock_Record'Class) return Boolean is
      T  : constant Gint64 := Clock.Get_Frame_Time;
      DT : constant Float := (if Last_Time = 0 then 0.016 else Float (T - Last_Time) / 1.0E6);
   begin
      Last_Time := T;
      Gamepad.Poll (DT);
      Maps.Poll (DT);
      Install_Events;
      if Pending_Frames > 0 then
         Pending_Frames := Pending_Frames - 1;
         if Pending_Frames = 0 then
            Finish_Load;
         end if;
         Input.End_Frame;
         Gamepad.End_Frame;
      elsif not Maps.Loaded then
         Setup_Frame (DT);
      else
         if State.Mode = Title then
            Title_Input;
         end if;
         Game.Frame (DT);
      end if;
      W.Queue_Draw;
      return True;
   end On_Tick;

   function On_Key_Press (Self : access Gtk_Widget_Record'Class; Event : Gdk_Event_Key) return Boolean is
      pragma Unreferenced (Self);
   begin
      Input.Press (Event.Keyval);
      return True;
   end On_Key_Press;

   function On_Key_Release (Self : access Gtk_Widget_Record'Class; Event : Gdk_Event_Key) return Boolean is
      pragma Unreferenced (Self);
   begin
      Input.Release (Event.Keyval);
      return True;
   end On_Key_Release;

   function On_Button_Press (Self : access Gtk_Widget_Record'Class; Event : Gdk_Event_Button) return Boolean is
      pragma Unreferenced (Self);
   begin
      if Event.Button = 1 then
         Input.Mouse_Down := True;
         Input.Mouse_Clicked := True;
         Input.Mouse_X := Float (Event.X);
         Input.Mouse_Y := Float (Event.Y);
      end if;
      return True;
   end On_Button_Press;

   function On_Button_Release (Self : access Gtk_Widget_Record'Class; Event : Gdk_Event_Button) return Boolean is
      pragma Unreferenced (Self);
   begin
      if Event.Button = 1 then
         Input.Mouse_Down := False;
      end if;
      return True;
   end On_Button_Release;

   function On_Motion (Self : access Gtk_Widget_Record'Class; Event : Gdk_Event_Motion) return Boolean is
      pragma Unreferenced (Self);
   begin
      Input.Mouse_X := Float (Event.X);
      Input.Mouse_Y := Float (Event.Y);
      return True;
   end On_Motion;

   function On_Focus_Out (Self : access Gtk_Widget_Record'Class; Event : Gdk_Event_Focus) return Boolean is
      pragma Unreferenced (Self, Event);
   begin
      Input.Release_All;
      return False;
   end On_Focus_Out;

   procedure On_Destroy (Self : access Gtk_Widget_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Maps.Stop;
      Sound.Stop;
      Gtk.Main.Main_Quit;
   end On_Destroy;

   procedure Run_Window is
      Id : Guint;
      pragma Unreferenced (Id);
   begin
      Gtk.Main.Init;
      Gtk_New (Win);
      Win.Set_Title ("PAVÉ");
      Win.Set_Default_Size (1280, 800);
      Win.Set_Position (Gtk.Enums.Win_Pos_Center);
      Gtk_New (Area);
      Win.Add (Area);
      Area.Add_Events (Button_Press_Mask or Button_Release_Mask or Pointer_Motion_Mask);
      Area.On_Draw (On_Draw'Access);
      Area.On_Button_Press_Event (On_Button_Press'Access);
      Area.On_Button_Release_Event (On_Button_Release'Access);
      Area.On_Motion_Notify_Event (On_Motion'Access);
      Win.On_Key_Press_Event (On_Key_Press'Access);
      Win.On_Key_Release_Event (On_Key_Release'Access);
      Win.On_Focus_Out_Event (On_Focus_Out'Access);
      Win.On_Destroy (On_Destroy'Access);
      Id := Area.Add_Tick_Callback (On_Tick'Access);
      Sound.Start;
      Win.Show_All;
      Gtk.Main.Main;
   end Run_Window;

   ------------------------------------------------------------------ headless bench
   procedure Step (Seconds : Float) is
   begin
      for I in 1 .. Integer (Seconds * 60.0) loop
         Game.Frame (1.0 / 60.0);
      end loop;
   end Step;

   procedure Shot (Path : String; Frames : Positive := 1; Ms : out Float) is
      S  : constant Cairo_Surface := Create (Cairo_Format_ARGB32, Gint (Screen_W), Gint (Screen_H));
      Cr : constant Cairo_Context := Create (S);
      St : Cairo_Status;
      T0 : constant Ada.Calendar.Time := Ada.Calendar.Clock;
   begin
      for I in 1 .. Frames loop
         Render.Draw (Cr);
      end loop;
      Ms := Float (Ada.Calendar."-" (Ada.Calendar.Clock, T0)) * 1000.0 / Float (Frames);
      St := Cairo.Png.Write_To_Png (S, Path);
      pragma Unreferenced (St);
      Destroy (Cr);
      Cairo.Surface.Destroy (S);
   end Shot;

   Shot_Dir : Unbounded_String;
   procedure Secret_Shot (Name : String) is
      Ms : Float;
      pragma Warnings (Off, Ms);
   begin
      Shot (To_String (Shot_Dir) & "/" & Name & ".png", 1, Ms);
   end Secret_Shot;

   --  ./pave --tour <dir> : a screenshot at a number of landmarks (and the edge of the world)
   procedure Tour (Out_Dir : String) is
      Ms : Float;
      pragma Warnings (Off, Ms);
      Paris_Tour : constant String :=
        "Tour Eiffel;Arc de Triomphe;Montmartre;Gare du Nord;Bastille;Pere-Lachaise;Notre-Dame;"
        & "Porte Maillot;Porte de Vincennes;Place d'Italie";

      function File_Name (S : String) return String is
         F : String := S;
      begin
         for C of F loop
            if C not in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' then
               C := '_';
            end if;
         end loop;
         return F;
      end File_Name;
   begin
      Screen_W := 1280.0; Screen_H := 800.0;
      Load_All;
      Game.Start_Game;
      Cam_Scale := 0.55;        --  zoomed out to see more of each area
      for I in 1 .. 20 loop
         declare
            P : constant Unbounded_String := To_Unbounded_String (World.Meta_Item ("tour", Paris_Tour, I));
         begin
         exit when P = Null_Unbounded_String;
         for L of World.Landmarks.all loop
            if L.Name = P then
               declare
                  N : constant Integer := World.Nearest (World.Ped_Graph, L.X, L.Y, 200.0);
               begin
                  if N >= 0 then
                     Peds (Player).X := World.NX (World.Ped_Graph, N);
                     Peds (Player).Y := World.NY (World.Ped_Graph, N);
                     Cam_X := Peds (Player).X; Cam_Y := Peds (Player).Y;
                     Step (3.0);
                     Shot (Out_Dir & "/" & File_Name (To_String (P)) & ".png", 12, Ms);   --  let tiles stream in
                     Put_Line ("tour: " & To_String (P) & " - "
                               & World.Street_At (Peds (Player).X, Peds (Player).Y));
                  end if;
               end;
            end if;
         end loop;
         end;
      end loop;
      Cam_Scale := 1.0;
      declare
         St : constant Cairo_Status := Cairo.Png.Write_To_Png (World_Render.Minimap, Out_Dir & "/overview.png");
         pragma Unreferenced (St);
      begin
         Put_Line ("tour: whole map -> overview.png");
      end;
   end Tour;

   procedure Bench (Out_Dir : String) is
      Ms : Float;
      function Img (F : Float) return String is (Integer'Image (Integer (F)));
   begin
      Screen_W := 1400.0; Screen_H := 850.0;
      Load_All;
      Step (0.5);
      Shot (Out_Dir & "/title.png", 1, Ms);
      Put_Line ("render title:" & Img (Ms) & " ms");
      Input.Hit (Input.K_Enter) := True;
      Step (2.0);
      Shot (Out_Dir & "/foot.png", 10, Ms);
      Put_Line ("render on foot:" & Img (Ms) & " ms/frame");
      --  traffic health
      Step (60.0);
      declare
         N, Stopped : Natural := 0;
         Sum : Float := 0.0;
      begin
         for C of Cars loop
            if C.Active and then C.Driver = AI_Driver and then C.AI.Mode = Traffic then
               N := N + 1;
               Sum := Sum + Physics.Speed (C);
               if Physics.Speed (C) < 0.5 then
                  Stopped := Stopped + 1;
               end if;
            end if;
         end loop;
         Put_Line ("traffic after 60 s:" & N'Image & " cars, avg speed"
                   & Float'Image (Sum / Float (Natural'Max (N, 1))) & " m/s, stopped" & Stopped'Image);
         Game.Traffic_Report;
      end;
      --  get into a car and drive a bit
      declare
         P  : Ped renames Peds (Player);
         CI : Car_Ref := 0;
         BD : Float := Float'Last;
      begin
         for I in Cars'Range loop
            if Cars (I).Active and then Cars (I).Driver = No_Driver and then not Cars (I).Dead then
               declare
                  D : constant Float := Hypot (Cars (I).X - P.X, Cars (I).Y - P.Y);
               begin
                  if D < BD then
                     BD := D; CI := I;
                  end if;
               end;
            end if;
         end loop;
         if CI /= 0 then
            --  drive with the (simulated) controller: Y enters, RT accelerates, LS steers
            P.X := Cars (CI).X; P.Y := Cars (CI).Y;
            Gamepad.Hit (Gamepad.Y) := True;
            Step (0.1);
            Put_Line ("pad: Y entered car:" & Boolean'Image (Player_Car = CI));
            declare
               X0 : constant Float := Cars (CI).X;
               Y0 : constant Float := Cars (CI).Y;
               A0 : constant Float := Cars (CI).A;
            begin
               Gamepad.RT := 1.0; Gamepad.LX := 0.6;
               Step (1.2);
               Put_Line ("pad: RT+LS moved" & Img (Hypot (Cars (CI).X - X0, Cars (CI).Y - Y0)) & " m, turned"
                         & Img (abs (Cars (CI).A - A0) * 57.3) & " deg, speed"
                         & Img (Physics.Speed (Cars (CI)) * 3.6) & " km/h");
               Gamepad.RT := 0.0; Gamepad.LX := 0.0;
               Gamepad.LT := 1.0;
               Step (1.5);
               Gamepad.LT := 0.0;
               Put_Line ("pad: LT braked to" & Img (Physics.Speed (Cars (CI)) * 3.6) & " km/h");
            end;
            Shot (Out_Dir & "/drive.png", 10, Ms);
            Put_Line ("render driving:" & Img (Ms) & " ms/frame");
            Gamepad.Hit (Gamepad.Y) := True;
            Step (0.1);
            Put_Line ("pad: Y exited car:" & Boolean'Image (Player_Car = 0));
            declare
               X0 : constant Float := P.X;
               A0 : constant Integer := Ammo (1);
            begin
               Gamepad.LX := 1.0;
               Step (1.0);
               Gamepad.LX := 0.0;
               Gamepad.RX := -1.0; Gamepad.RT := 1.0;
               Step (1.0);
               Gamepad.RX := 0.0; Gamepad.RT := 0.0;
               Put_Line ("pad: LS walked" & Img (abs (P.X - X0)) & " m, RT fired" & Img (Float (A0 - Ammo (1)))
                         & " shots, RS aim angle" & Img (P.A * 57.3) & " deg");
            end;
            Gamepad.Hit (Gamepad.RB) := True;
            Step (0.05);
            Put_Line ("pad: RB weapon -> " & To_String (Weapon_Names (Weapon)));
         end if;
      end;
      --  police chase
      Heat := 2.5; Seen_T := 0.0;
      declare
         Min_D : Float := Float'Last;
         T     : Float := 0.0;
      begin
         while T < 60.0 and then State.Mode = Play loop
            Step (0.5);
            T := T + 0.5;
            for C of Cars loop
               if C.Active and then C.Driver = AI_Driver and then C.AI.Mode = Pursuit then
                  Min_D := Float'Min (Min_D, Hypot (C.X - Peds (Player).X, C.Y - Peds (Player).Y));
               end if;
            end loop;
            if T = 8.0 then
               Shot (Out_Dir & "/chase.png", 1, Ms);
               Put_Line ("render chase:" & Img (Ms) & " ms");
            end if;
         end loop;
         Put_Line ("chase: closest police" & Img (Min_D) & " m, mode " & State.Mode'Image
                   & " after" & Img (T) & " s, busted=" & Boolean'Image (Busted));
         Shot (Out_Dir & "/end.png", 1, Ms);
         Put_Line ("render end:" & Img (Ms) & " ms");
      end;
   end Bench;

   --  prints live controller state, e.g. ./pave --padtest 10
   procedure Pad_Test (Seconds : Float) is
      T : Float := 0.0;
      function F (V : Float) return String is
         S : constant String := Integer'Image (Integer (V * 100.0));
      begin
         return S;
      end F;
   begin
      while T < Seconds loop
         Gamepad.Poll (0.1);
         if Gamepad.Changed then
            Gamepad.Changed := False;
            Put_Line ((if Gamepad.Connected then "connected: " & To_String (Gamepad.Name)
                       else "no controller"));
         end if;
         if Gamepad.Connected then
            Put ("LS" & F (Gamepad.LX) & F (Gamepad.LY) & "  RS" & F (Gamepad.RX) & F (Gamepad.RY)
                 & "  LT" & F (Gamepad.LT) & "  RT" & F (Gamepad.RT) & "  buttons:");
            for B in Gamepad.Button loop
               if Gamepad.Down (B) then
                  Put (" " & Gamepad.Button'Image (B));
               end if;
            end loop;
            New_Line;
         end if;
         Gamepad.End_Frame;
         delay 0.1;
         T := T + 0.1;
      end loop;
   end Pad_Test;

   --  plays every sound effect, then an engine run-up and the siren
   procedure Sound_Test is
   begin
      Sound.Start;
      delay 0.5;
      if not Sound.Running then
         Put_Line ("no audio device / PulseAudio server available");
         return;
      end if;
      for E in Sound.Effect loop
         Put_Line ("effect: " & Sound.Effect'Image (E));
         Sound.Play (E);
         delay (if E = Sound.Explosion or else E = Sound.Splash then 1.6 else 0.8);
      end loop;
      Put_Line ("city ambience");
      Sound.Set_Ambience (True);
      delay 2.5;
      Sound.Set_Ambience (False);
      delay 1.0;
      Put_Line ("engine: idle -> 140 km/h -> idle");
      for I in 0 .. 40 loop
         Sound.Set_Engine (True, Float (I));
         delay 0.08;
      end loop;
      for I in reverse 0 .. 40 loop
         Sound.Set_Engine (True, Float (I));
         delay 0.03;
      end loop;
      Sound.Set_Engine (False, 0.0);
      delay 0.5;
      Put_Line ("siren");
      Sound.Set_Siren (1.0);
      delay 2.5;
      Sound.Set_Siren (0.0);
      delay 0.5;
      Sound.Stop;
   end Sound_Test;

   ------------------------------------------------------------------ README media
   --  ./pave --capture <dir> : plays scripted scenes headless and writes PNG frame
   --  sequences (20 fps) plus stills; tools/make_media.sh turns them into GIFs.
   procedure Capture (Out_Dir : String) is
      Frame_No : Natural := 0;

      procedure Still (Name : String) is
         Ms : Float;
      begin
         Shot (Out_Dir & "/" & Name & ".png", 1, Ms);
         Put_Line ("still " & Name & " (" & Integer'Image (Integer (Ms)) & " ms)");
      end Still;

      --  simulate Seconds at 60 Hz, calling Control before every step and
      --  writing every third frame to <dir>/<Scene>/NNNN.png
      procedure Film (Scene : String; Seconds : Float;
                        Control : access procedure := null; Write : Boolean := True) is
         Dir : constant String := Out_Dir & "/" & Scene;
         Ms  : Float;
         pragma Warnings (Off, Ms);
      begin
         if Write and then not Ada.Directories.Exists (Dir) then
            Ada.Directories.Create_Path (Dir);
         end if;
         Frame_No := 0;
         for I in 1 .. Integer (Seconds * 60.0) loop
            if Control /= null then
               Control.all;
            end if;
            Game.Frame (1.0 / 60.0);
            if Write and then I mod 3 = 0 then
               Frame_No := Frame_No + 1;
               declare
                  N : constant String := Integer'Image (10_000 + Frame_No);
               begin
                  Shot (Dir & "/" & N (3 .. N'Last) & ".png", 1, Ms);
               end;
            end if;
         end loop;
         if Write then
            Put_Line ("scene " & Scene & ":" & Frame_No'Image & " frames");
         end if;
      end Film;

      function Nearest_Free_Car (X, Y, Min_D : Float; Not_Car : Car_Ref := 0) return Car_Ref is
         Best   : Car_Ref := 0;
         Best_D : Float := Float'Last;
      begin
         for I in Cars'Range loop
            declare
               C : Car renames Cars (I);
               D : constant Float := Hypot (C.X - X, C.Y - Y);
            begin
               if C.Active and then C.Driver = No_Driver and then not C.Dead and then I /= Not_Car
                 and then C.Kind not in Bus | Police and then D >= Min_D and then D < Best_D
               then
                  Best := I; Best_D := D;
               end if;
            end;
         end loop;
         return Best;
      end Nearest_Free_Car;

      --  stand the player beside a car, facing it
      procedure Walk_Up_To (CI : Car_Ref; Dist : Float) is
         C : Car renames Cars (CI);
         P : Ped renames Peds (Player);
      begin
         for K in 0 .. 15 loop
            declare
               A  : constant Float := C.A + Pi / 2.0 + Float (K) * Pi / 8.0;
               X  : constant Float := C.X + Cos (A) * Dist;
               Y  : constant Float := C.Y + Sin (A) * Dist;
            begin
               if not World.Blocked (X, Y) then
                  P.X := X; P.Y := Y;
                  P.A := Arctan (C.Y - Y, C.X - X);
                  return;
               end if;
            end;
         end loop;
      end Walk_Up_To;

      Target   : Car_Ref := 0;
      Want_Spd : Float := 14.0;

      procedure Clear_Pad is
      begin
         Gamepad.LX := 0.0; Gamepad.LY := 0.0; Gamepad.RX := 0.0; Gamepad.RY := 0.0;
         Gamepad.LT := 0.0; Gamepad.RT := 0.0;
         Gamepad.Down := (others => False);
      end Clear_Pad;

      --  on foot: aim the right stick at Target and hold the trigger until it blows up
      procedure Shoot_Target is
         P : Ped renames Peds (Player);
         C : Car renames Cars (Target);
      begin
         Clear_Pad;
         if not C.Dead then
            declare
               A : constant Float := Arctan (C.Y - P.Y, C.X - P.X);
            begin
               Gamepad.RX := Cos (A); Gamepad.RY := Sin (A); Gamepad.RT := 1.0;
            end;
         end if;
      end Shoot_Target;

      --  in a car: follow the road graph with the gamepad, like a traffic driver
      --  traffic in our way: nearest car in a corridor ahead (Lat > 0 = right of us)
      procedure Look_Ahead (C : Car; Dist, Lat : out Float) is
         FX : constant Float := Cos (C.A);
         FY : constant Float := Sin (C.A);
      begin
         Dist := Float'Last; Lat := 0.0;
         for I in Cars'Range loop
            if Cars (I).Active and then I /= Player_Car then
               declare
                  O : Car renames Cars (I);
                  F : constant Float := (O.X - C.X) * FX + (O.Y - C.Y) * FY;
                  L : constant Float := -(O.X - C.X) * FY + (O.Y - C.Y) * FX;
               begin
                  if F > 1.0 and then F < 16.0 + Physics.Speed (C) * 0.6 and then abs L < 2.6
                    and then F < Dist
                  then
                     Dist := F; Lat := L;
                  end if;
               end;
            end if;
         end loop;
      end Look_Ahead;

      procedure Drive (C : in out Car) is
         TX, TY    : Float;
         Dist, Lat : Float;
      begin
         --  overtake on the left when something blocks our lane, then merge back
         Look_Ahead (C, Dist, Lat);
         C.AI.Lane := (if Dist < Float'Last then 2.1 - 3.6 * (if Lat > 0.0 then 1.0 else 0.5) else 2.1);
         Physics.Extend_Random (C);
         Physics.AI_Target (C, Float'Max (7.0, Physics.Speed (C) * 0.75), TX, TY);
         declare
            D   : constant Float := Ang_Diff (C.A, Arctan (TY - C.Y, TX - C.X));
            B   : constant Float := Physics.Bend (C);
            Spd : constant Float := Want_Spd * (if B > 1.0 then 0.4 elsif B > 0.5 then 0.65 else 1.0);
            Err : constant Float := Float'Min (Spd, (if Dist < 7.0 then 3.0 else Spd)) - Physics.Fwd_Speed (C);
         begin
            Gamepad.LX := Clamp (D * 2.4, -1.0, 1.0);
            Gamepad.RT := Clamp (Err / 4.0, 0.0, 1.0);
            Gamepad.LT := Clamp (-Err / 5.0, 0.0, 1.0);
         end;
      end Drive;

      procedure Autopilot is
      begin
         Clear_Pad;
         if Player_Car /= 0 then
            Drive (Cars (Player_Car));
         end if;
      end Autopilot;

      procedure Start_Autopilot is
         C : Car renames Cars (Player_Car);
         N : constant Integer := World.Nearest (World.Car_Graph, C.X + Cos (C.A) * 6.0,
                                                C.Y + Sin (C.A) * 6.0, 80.0);
      begin
         C.AI.Len := 1; C.AI.Idx := 1;
         C.AI.Path (1) := Natural'Max (N, 0);
         C.AI.Lane := 2.1;
      end Start_Autopilot;

   begin
      Screen_W := 1280.0; Screen_H := 800.0;
      Load_All;
      Seed (Integer'Value (Ada.Environment_Variables.Value ("PAVE_SEED", "1")));
      Step (0.5);
      Still ("title");
      Input.Hit (Input.K_Enter) := True;
      Step (2.5);
      Still ("saint-sulpice");

      --  1. shoot up a parked car until it explodes
      Weapon := 2; Ammo (2) := 400;
      Target := Nearest_Free_Car (Peds (Player).X, Peds (Player).Y, 0.0);
      if Target /= 0 then
         Walk_Up_To (Target, 9.0);
         Cam_Scale := 1.3;
         Step (0.6);
         Film ("explosion", 7.0, Shoot_Target'Access);
      end if;
      Clear_Pad;

      --  2. steal a car and cruise through Saint-Germain
      Heat := 0.0; Step (1.0);
      Target := Nearest_Free_Car (Peds (Player).X, Peds (Player).Y, 20.0, Target);
      if Target /= 0 then
         Walk_Up_To (Target, 2.5);
         Step (0.5);
         declare
            procedure Get_In is
            begin
               Clear_Pad;
               if Player_Car = 0 and then Frame_No = 15 then
                  Gamepad.Hit (Gamepad.Y) := True;
               end if;
               if Player_Car /= 0 then
                  if Cars (Player_Car).AI.Len = 0 then
                     Start_Autopilot;
                  end if;
                  Autopilot;
               end if;
            end Get_In;
         begin
            Cars (Target).AI.Len := 0;
            Want_Spd := 15.0;
            Cam_Scale := 1.7;
            Film ("drive", 9.0, Get_In'Access);
         end;
         Still ("drive");
      end if;

      --  3. three stars: police pursuit
      if Player_Car /= 0 then
         Heat := 3.2; Seen_T := 0.0;
         Want_Spd := 20.0;
         Film ("chase", 4.0, Autopilot'Access, Write => False);   --  let them catch up
         Film ("chase", 10.0, Autopilot'Access);
         Put_Line ("chase ended: in car=" & Boolean'Image (Player_Car /= 0) & " mode=" & State.Mode'Image
                   & " stars=" & Game.Stars'Image);
         Still ("chase");
      end if;
      Clear_Pad;

      --  4. - 6.: the vehicles, each from a fresh start at Saint-Sulpice
      declare
         --  a vehicle of kind K on open ground (or water, for boats) near (X, Y), facing A if it fits
         function Place (K : Car_Type; X, Y, A : Float) return Car_Ref is
            T : Car;
         begin
            T.Kind := K;
            for R in 0 .. 40 loop
               for D in 0 .. 15 loop
                  T.X := X + Cos (Float (D) * Pi / 8.0) * Float (R) * 2.0;
                  T.Y := Y + Sin (Float (D) * Pi / 8.0) * Float (R) * 2.0;
                  for H in 0 .. 7 loop
                     T.A := A + Float (H) * Pi / 4.0;
                     if Physics.Fits (T) then
                        return Physics.Alloc_Car (K, T.X, T.Y, T.A);
                     end if;
                  end loop;
               end loop;
            end loop;
            return 0;
         end Place;

         procedure Fresh_Start is
         begin
            Load_All;
            Game.Start_Game;
            Step (1.0);
            Clear_Pad;
            Cam_Scale := 1.5;
         end Fresh_Start;

         procedure Board (CI : Car_Ref) is
         begin
            Walk_Up_To (CI, Params (Cars (CI).Kind).Wid / 2.0 + 1.2);
            Step (0.2);
            Gamepad.Hit (Gamepad.Y) := True;
            Step (0.3);
         end Board;

         Veh, Target : Car_Ref := 0;
         Clock       : Float := 0.0;

         --  the tank rolls forward, swings its turret onto a parked car and fires
         procedure Tank_Pad is
         begin
            Clear_Pad;
            Clock := Clock + 1.0 / 60.0;
            if Player_Car = 0 then
               return;
            end if;
            declare
               C : Car renames Cars (Player_Car);
            begin
               Gamepad.RT := (if Clock < 2.0 then 0.6 else 0.0);
               Gamepad.LT := (if Clock in 2.0 .. 3.0 then 0.6 else 0.0);
               if Target /= 0 then
                  declare
                     A : constant Float := Arctan (Cars (Target).Y - C.Y, Cars (Target).X - C.X);
                  begin
                     Gamepad.RX := Cos (A); Gamepad.RY := Sin (A);
                     Gamepad.Down (Gamepad.X) := Clock > 3.6 and then Clock < 3.7;
                  end;
               end if;
            end;
         end Tank_Pad;

         --  out on the water: full ahead, steering for the most open water
         procedure Boat_Pad is
         begin
            Clear_Pad;
            if Player_Car = 0 then
               return;
            end if;
            declare
               C    : Car renames Cars (Player_Car);
               Best : Float := C.A;
               BF   : Float := -1.0;
            begin
               for K in -4 .. 4 loop
                  declare
                     H : constant Float := C.A + Float (K) * 0.25;
                     F : Float := 0.0;
                  begin
                     while F < 60.0 and then World.Navigable (C.X + Cos (H) * F, C.Y + Sin (H) * F) loop
                        F := F + 2.0;
                     end loop;
                     F := F - abs Float (K) * 3.0;
                     if F > BF then
                        BF := F; Best := H;
                     end if;
                  end;
               end loop;
               Gamepad.RT := 0.8;
               Gamepad.LX := Clamp (Ang_Diff (C.A, Best) * 2.0, -1.0, 1.0);
            end;
         end Boat_Pad;

         --  lift off turning slowly, then fly over the rooftops
         procedure Heli_Pad is
         begin
            Clear_Pad;
            Clock := Clock + 1.0 / 60.0;
            Gamepad.LX := (if Clock < 3.5 then 0.35 else 0.0);
            Gamepad.RT := (if Clock < 3.0 then 0.0 else 1.0);
         end Heli_Pad;
      begin
         --  the tank scene is on Place de la Concorde, in All of Paris (if it is installed)
         if Maps.Installed (Maps.Large) then
            Map_Override := To_Unbounded_String (Maps.Path (Maps.Large));
         end if;
         Fresh_Start;
         for L of World.Landmarks.all loop
            if L.Name = "Concorde" then
               declare
                  N : constant Integer := World.Nearest (World.Car_Graph, L.X, L.Y, 120.0);
               begin
                  if N >= 0 then
                     Peds (Player).X := World.NX (World.Car_Graph, N);
                     Peds (Player).Y := World.NY (World.Car_Graph, N);
                     Cam_X := Peds (Player).X; Cam_Y := Peds (Player).Y;
                     for C of Cars loop         --  a clear stage
                        if C.Active and then Hypot (C.X - Cam_X, C.Y - Cam_Y) < 60.0 then
                           C.Active := False;
                        end if;
                     end loop;
                  end if;
               end;
            end if;
         end loop;
         Veh := Place (Tank, Peds (Player).X, Peds (Player).Y, Pi);   --  facing west, up the Champs-Elysees
         Map_Override := Null_Unbounded_String;
         if Veh /= 0 then
            Target := Place (Sedan, Cars (Veh).X + Cos (Cars (Veh).A) * 30.0,
                             Cars (Veh).Y + Sin (Cars (Veh).A) * 30.0, Cars (Veh).A + Pi / 2.0);
            Board (Veh);
            Clock := 0.0;
            Film ("tank", 7.0, Tank_Pad'Access);
         end if;

         Fresh_Start;
         Veh := 0;
         for I in Cars'Range loop          --  the moored speedboat nearest to the start
            if Cars (I).Active and then Cars (I).Kind = Speedboat and then Cars (I).Driver = No_Driver
              and then (Veh = 0 or else Hypot (Cars (I).X - Peds (Player).X, Cars (I).Y - Peds (Player).Y)
                                        < Hypot (Cars (Veh).X - Peds (Player).X, Cars (Veh).Y - Peds (Player).Y))
            then
               Veh := I;
            end if;
         end loop;
         if Veh /= 0 then
            Board (Veh);
            Step (0.5);
            Film ("boat", 8.0, Boat_Pad'Access);
         end if;

         Fresh_Start;
         Veh := Place (Helicopter, Peds (Player).X, Peds (Player).Y, 0.0);
         if Veh /= 0 then
            Board (Veh);
            Clock := 0.0;
            Cam_Scale := 2.0;          --  the camera zooms out with height: keep the helicopter big
            Film ("helicopter", 8.0, Heli_Pad'Access);
         end if;
      end;
      Clear_Pad;
      Cam_Scale := 1.0;
   end Capture;

   procedure Usage is
   begin
      Put_Line ("usage: pave [--bench DIR | --selftest | --secretstest [DIR] | --capture DIR | --tour DIR");
      Put_Line ("             | --soundtest | --padtest [SECONDS]]");
      Put_Line ("Without options the game window opens. PAVE_MAP=file.bin picks a map file.");
   end Usage;

   procedure Run is
   begin
      if Argument_Count >= 1 and then Argument (1) not in "--bench" | "--selftest" | "--secretstest"
        | "--capture" | "--tour" | "--soundtest" | "--padtest"
      then
         Usage;            --  never fall through to the game window on an unknown option
         Set_Exit_Status (Failure);
         return;
      end if;
      if Argument_Count >= 1 and then Argument (1) in "--bench" | "--selftest" | "--capture" | "--tour" then
         Secrets.Persist := False;     --  automated runs never touch the player's discoveries
      end if;
      Maps.Choose_Startup;
      if Argument_Count >= 1 and then Argument (1) /= "--soundtest" and then Argument (1) /= "--padtest"
        and then not Have_Map
      then
         Put_Line ("No world installed yet. Run:  python3 tools/get_map.py   (or start ./pave to download one)");
         Set_Exit_Status (Failure);
         return;
      end if;
      if Argument_Count >= 1 and then Argument (1) = "--soundtest" then
         Sound_Test;
      elsif Argument_Count >= 1 and then Argument (1) = "--padtest" then
         Pad_Test ((if Argument_Count >= 2 then Float'Value (Argument (2)) else 10.0));
      elsif Argument_Count >= 1 and then Argument (1) = "--secretstest" then
         Secrets.Persist := False;
         Screen_W := 1280.0; Screen_H := 800.0;
         Load_All;
         if Argument_Count >= 2 then
            Shot_Dir := To_Unbounded_String (Argument (2));
            Secrets.Shot := Secret_Shot'Access;
         end if;
         Secrets.Self_Test;
      elsif Argument_Count >= 1 and then Argument (1) = "--selftest" then
         Screen_W := 1280.0; Screen_H := 800.0;
         Load_All;
         if Argument_Count >= 2 then
            Shot_Dir := To_Unbounded_String (Argument (2));
            Secrets.Shot := Secret_Shot'Access;
         end if;
         Game.Self_Test;
      elsif Argument_Count >= 1 and then Argument (1) = "--capture" then
         Capture ((if Argument_Count >= 2 then Argument (2) else "media"));
      elsif Argument_Count >= 1 and then Argument (1) = "--tour" then
         Tour ((if Argument_Count >= 2 then Argument (2) else "."));
      elsif Argument_Count >= 1 and then Argument (1) = "--bench" then
         Bench ((if Argument_Count >= 2 then Argument (2) else "."));
      else
         if Have_Map then
            Load_All;
         end if;
         Run_Window;
      end if;
   end Run;

end App;
