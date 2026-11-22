-- ***************************************************************************
--                      PAVÉ - Secrets
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

with Ada.Text_IO;
with Ada.Strings.Unbounded;             use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Characters.Handling;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Util;    use Util;
with State;   use State;
with World;   use World;
with Physics; use Physics;
with Gfx;     use Gfx;
with Game;
with Sound;
with Input;
with Gamepad;
with Maps;

package body Secrets is

   function "+" (S : String) return Unbounded_String renames To_Unbounded_String;

   Gold  : constant RGB := (1.0, 0.82, 0.29);

   ------------------------------------------------------------------ data
   type Pave is record
      X, Y  : Float := 0.0;
      Found : Boolean := False;
   end record;
   Max_Paves : constant := 60;
   Paves     : array (1 .. Max_Paves) of Pave;
   N_Paves   : Natural := 0;

   type Manhole is record
      Name : Unbounded_String;
      X, Y : Float := 0.0;
      Used : Boolean := False;
   end record;
   Manholes : array (1 .. 16) of Manhole;
   N_Man    : Natural := 0;

   subtype Secret_Car is Car_Type range Escargot .. Plane;
   type Car_Slot is record
      Has    : Boolean := False;      --  its anchor is on this map
      AX, AY : Float := 0.0;
      Ref    : Car_Ref := 0;
      Serial : Natural := 0;
      Found  : Boolean := False;
      Text   : Unbounded_String;        --  the city's own line for it ("#car:Name|text")
   end record;
   Specials : array (Secret_Car) of Car_Slot;

   type Cheat_Id is (Croissant, Liberte, Greve, Baguette, Char);
   Cheat_Word  : constant array (Cheat_Id) of Unbounded_String :=
     (+"CROISSANT", +"LIBERTE", +"GREVE", +"BAGUETTE", +"CHAR");
   Cheat_Found : array (Cheat_Id) of Boolean := (others => False);

   --  per-city words and titles (the map's settings; Paris otherwise)
   function Word (C : Cheat_Id) return String is
     (World.Meta ("cheat_" & Ada.Characters.Handling.To_Lower (Cheat_Id'Image (C)), To_String (Cheat_Word (C))));
   function Title (Key, Default : String) return String is (World.Meta ("title_" & Key, Default));
   function City return String is (World.Meta ("city", "Paris"));

   type Life_Id is (Mime_Seen, Musician_Seen, Manif_Seen, Pigeons_Seen);
   Life_Name  : constant array (Life_Id) of Unbounded_String :=
     (+"Mime", +"Accordionist", +"Protest march", +"Pigeons");
   Life_Found : array (Life_Id) of Boolean := (others => False);
   Flocks     : Natural := 0;

   Dirty  : Boolean := False;
   Save_T : Float := 0.0;

   --  pigeons
   type Bird_State is (Ground, Flying);
   type Pigeon is record
      Active : Boolean := False;
      St     : Bird_State := Ground;
      X, Y, Z, VX, VY, VZ, A : Float := 0.0;
      T, Hop_T : Float := 0.0;
      Flock  : Natural := 0;
   end record;
   Birds        : array (1 .. 240) of Pigeon;
   Flock_Count  : Natural := 0;
   Counted      : array (0 .. 63) of Boolean := (others => True);
   Flock_T      : Float := 1.0;
   Flutter_Cool : Float := 0.0;

   --  street characters
   Mime_Ref, Musician_Ref : Ped_Ref := 0;
   Mime_T     : Float := 20.0;
   Musician_T : Float := 35.0;
   Listen_T   : Float := 0.0;

   Max_March : constant := 24;
   type Member_Array is array (1 .. Max_March) of Ped_Ref;
   type Node_Array is array (1 .. 64) of Natural;
   type March_State is record
      Active  : Boolean := False;
      Path    : Node_Array := (others => 0);
      Len     : Natural := 0;
      Idx     : Positive := 1;
      LX, LY  : Float := 0.0;
      DX, DY  : Float := 1.0;
      T       : Float := 0.0;
      Members : Member_Array := (others => 0);
   end record;
   March   : March_State;
   March_T : Float := 80.0;

   --  catacombs, strike, misc
   Fade_T, Fade_Max : Float := 0.0;
   Fade_From  : Natural := 0;
   Moved      : Boolean := False;
   Strike_T   : Float := 0.0;
   Hint_Cool  : Float := 0.0;
   Drop_T     : Float := 0.0;
   Flame_T    : Float := 0.0;
   Respawn_T  : Float := 0.0;

   ------------------------------------------------------------------ small helpers
   function PX return Float is (Peds (Player).X);
   function PY return Float is (Peds (Player).Y);
   function On_Foot return Boolean is (Player /= 0 and then Player_Car = 0);
   function Dist (X, Y : Float) return Float is (Hypot (X - PX, Y - PY));

   function Strike return Boolean is (Strike_T > 0.0);
   function Busy return Boolean is (Fade_T > 0.0);

   function Img (N : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   function Found_Paves return Natural is
      N : Natural := 0;
   begin
      for I in 1 .. N_Paves loop
         if Paves (I).Found then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Found_Paves;

   function Respawn_Armor return Boolean is (Found_Paves >= Natural'Min (10, N_Paves));
   function Respawn_SMG return Boolean is (Found_Paves >= Natural'Min (20, N_Paves));

   --  a walkable spot off the roads, R0 .. R1 from the player (not on screen unless allowed)
   procedure Open_Spot (R0, R1 : Float; X, Y : out Float; Ok : out Boolean;
                        Visible_Ok : Boolean := False; Off_Road : Float := 8.0) is
   begin
      Ok := False; X := 0.0; Y := 0.0;
      for Try in 1 .. 24 loop
         declare
            A : constant Float := Rand (0.0, 2.0 * Pi);
            R : constant Float := Rand (R0, R1);
            N : constant Integer := Nearest (Ped_Graph, PX + Cos (A) * R, PY + Sin (A) * R, 40.0);
         begin
            if N >= 0 then
               X := NX (Ped_Graph, N); Y := NY (Ped_Graph, N);
               if not Blocked (X, Y) and then In_Bounds (X, Y)
                 and then Nearest (Car_Graph, X, Y, Off_Road) < 0
                 and then (Visible_Ok or else not Game.On_Screen (X, Y, 10.0))
               then
                  Ok := True;
                  return;
               end if;
            end if;
         end;
      end loop;
   end Open_Spot;

   ------------------------------------------------------------------ save file
   procedure Save is
      F : Ada.Text_IO.File_Type;
      use Ada.Text_IO;
   begin
      Dirty := False;
      if not Persist then
         return;
      end if;
      Create (F, Out_File, Maps.Progress_Path);
      Put_Line (F, "# PAVE discoveries for this world");
      for I in 1 .. N_Paves loop
         if Paves (I).Found then
            Put_Line (F, "pave" & I'Image);
         end if;
      end loop;
      for K in Secret_Car loop
         if Specials (K).Found then
            Put_Line (F, "car " & Car_Type'Image (K));
         end if;
      end loop;
      for I in 1 .. N_Man loop
         if Manholes (I).Used then
            Put_Line (F, "hole" & I'Image);
         end if;
      end loop;
      for L in Life_Id loop
         if Life_Found (L) then
            Put_Line (F, "life " & Life_Id'Image (L));
         end if;
      end loop;
      for C in Cheat_Id loop
         if Cheat_Found (C) then
            Put_Line (F, "cheat " & Cheat_Id'Image (C));
         end if;
      end loop;
      Put_Line (F, "flocks" & Flocks'Image);
      Close (F);
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
   end Save;

   procedure Load is
      use Ada.Text_IO;
      F : File_Type;
   begin
      if not Persist then
         return;
      end if;
      Open (F, In_File, Maps.Progress_Path);
      while not End_Of_File (F) loop
         declare
            L  : constant String := Get_Line (F);
            Sp : constant Natural := Ada.Strings.Fixed.Index (L, " ");
         begin
            if Sp > 0 then
               declare
                  K : constant String := L (L'First .. Sp - 1);
                  V : constant String := Ada.Strings.Fixed.Trim (L (Sp + 1 .. L'Last), Ada.Strings.Both);
               begin
                  if K = "pave" and then Integer'Value (V) in 1 .. N_Paves then
                     Paves (Integer'Value (V)).Found := True;
                  elsif K = "car" then
                     Specials (Car_Type'Value (V)).Found := True;
                  elsif K = "hole" and then Integer'Value (V) in 1 .. N_Man then
                     Manholes (Integer'Value (V)).Used := True;
                  elsif K = "life" then
                     Life_Found (Life_Id'Value (V)) := True;
                  elsif K = "cheat" then
                     Cheat_Found (Cheat_Id'Value (V)) := True;
                  elsif K = "flocks" then
                     Flocks := Natural'Value (V);
                  end if;
               exception
                  when others => null;      --  ignore a damaged line
               end;
            end if;
         end;
      end loop;
      Close (F);
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
   end Load;

   procedure Discover (Text : String; Sub : String := "") is
   begin
      Game.Show_Big (Text, Gold, 3.0, Sub);
      Sound.Play (Sound.Chime, 0.8);
      Dirty := True;
   end Discover;

   ------------------------------------------------------------------ placement
   --  golden paves: dead-end footpaths and spots far from any road, spread out
   procedure Place_Paves is
      Target : constant Natural := (if W * H < 20.0E6 then 25 else 50);
      N      : constant Natural := Node_Count (Ped_Graph);
      type Cand is record
         X, Y, Best : Float;
      end record;
      type Cand_Array is array (Positive range <>) of Cand;
      type Cand_Access is access Cand_Array;
      C   : constant Cand_Access := new Cand_Array (1 .. Natural'Max (N, 1));
      NC  : Natural := 0;
   begin
      N_Paves := 0;
      for I in 0 .. N - 1 loop
         declare
            X : constant Float := NX (Ped_Graph, I);
            Y : constant Float := NY (Ped_Graph, I);
         begin
            if In_Bounds (X, Y) and then not Blocked (X, Y)
              and then ((Undirected_Degree (Ped_Graph, I) = 1 and then Nearest (Car_Graph, X, Y, 12.0) < 0)
                        or else Nearest (Car_Graph, X, Y, 22.0) < 0)
            then
               NC := NC + 1;
               C (NC) := (X, Y, Float'Last);
            end if;
         end;
      end loop;
      --  farthest-point sampling, with a little deterministic jitter
      while N_Paves < Natural'Min (Target, NC) loop
         declare
            Pick : Positive := 1;
            Best : Float := -1.0;
         begin
            for I in 1 .. NC loop
               declare
                  Score : constant Float := Float'Min (C (I).Best, 1.0E6) * (0.75 + 0.25 * Hash (Float (I) * 0.37));
               begin
                  if Score > Best then
                     Best := Score; Pick := I;
                  end if;
               end;
            end loop;
            N_Paves := N_Paves + 1;
            Paves (N_Paves) := (C (Pick).X, C (Pick).Y, False);
            for I in 1 .. NC loop
               C (I).Best := Float'Min (C (I).Best, Hypot (C (I).X - C (Pick).X, C (I).Y - C (Pick).Y));
            end loop;
         end;
      end loop;
   end Place_Paves;

   --  a spot near (AX, AY) where a car of kind K fits; 0 if none
   function Place_Car (K : Car_Type; AX, AY, Max_R : Float) return Car_Ref is
      T : Car;
   begin
      T.Kind := K;
      for Ring in 0 .. Natural (Max_R / 2.0) loop
         for Step in 0 .. Natural'Max (1, Ring * 6) - 1 loop
            declare
               R  : constant Float := Float (Ring) * 2.0;
               An : constant Float := Float (Step) * 2.0 * Pi / Float (Natural'Max (1, Ring * 6));
            begin
               T.X := AX + Cos (An) * R;
               T.Y := AY + Sin (An) * R;
               if In_Bounds (T.X, T.Y) and then not Blocked (T.X, T.Y) then
                  for H in 0 .. 11 loop
                     T.A := Float (H) * Pi / 12.0;
                     if Fits (T) then
                        return Alloc_Car (K, T.X, T.Y, T.A);
                     end if;
                  end loop;
               end if;
            end;
         end loop;
      end loop;
      return 0;
   end Place_Car;

   procedure Spawn_Special (K : Secret_Car) is
      S : Car_Slot renames Specials (K);
   begin
      S.Ref := Place_Car (K, S.AX, S.AY, 30.0);
      if S.Ref /= 0 then
         Cars (S.Ref).Keep := True;
         S.Serial := Cars (S.Ref).Serial;
      end if;
   end Spawn_Special;

   procedure Init is
   begin
      Birds := (others => <>);
      Mime_Ref := 0; Musician_Ref := 0;
      March := (others => <>);
      Fade_T := 0.0; Strike_T := 0.0;
      Mime_T := 20.0; Musician_T := 35.0; March_T := 80.0;
      Cheat_Found := (others => False);
      Life_Found := (others => False);
      Flocks := 0;
      for K in Secret_Car loop
         Specials (K) := (others => <>);
      end loop;
      Place_Paves;
      N_Man := 0;
      for L of Landmarks.all loop
         declare
            Name : constant String := To_String (L.Name);
         begin
            if Name'Length > 6 and then Name (Name'First .. Name'First + 5) = "#cata:" and then N_Man < Manholes'Last
            then
               declare
                  N : constant Integer := Nearest (Ped_Graph, L.X, L.Y, 40.0);
               begin
                  N_Man := N_Man + 1;
                  Manholes (N_Man) := (+Name (Name'First + 6 .. Name'Last),
                                       (if N >= 0 then NX (Ped_Graph, N) else L.X),
                                       (if N >= 0 then NY (Ped_Graph, N) else L.Y), False);
               end;
            elsif Name'Length > 5 and then Name (Name'First .. Name'First + 4) = "#car:" then
               begin
                  declare
                     Bar : constant Natural := Ada.Strings.Fixed.Index (Name, "|");
                     Last : constant Natural := (if Bar > 0 then Bar - 1 else Name'Last);
                     K : constant Car_Type := Car_Type'Value (Name (Name'First + 5 .. Last));
                  begin
                     if K in Secret_Car then
                        Specials (K).Has := True;
                        Specials (K).AX := L.X;
                        Specials (K).AY := L.Y;
                        Specials (K).Text := (if Bar > 0 then +Name (Bar + 1 .. Name'Last) else Null_Unbounded_String);
                     end if;
                  end;
               exception
                  when Constraint_Error => null;
               end;
            end if;
         end;
      end loop;
      for K in Secret_Car loop
         if Specials (K).Has then
            Spawn_Special (K);
         end if;
      end loop;
      Load;
   end Init;

   ------------------------------------------------------------------ paves
   procedure Update_Paves is
      R : constant Float := (if On_Foot then 1.4 else 2.4);
   begin
      for I in 1 .. N_Paves loop
         declare
            P : Pave renames Paves (I);
         begin
            if not P.Found and then abs (P.X - PX) < R and then abs (P.Y - PY) < R and then Dist (P.X, P.Y) < R then
               P.Found := True;
               Dirty := True;
               for K in 1 .. 10 loop
                  Game.Particle (P.X, P.Y, Spark);
               end loop;
               declare
                  N    : constant Natural := Found_Paves;
                  Msg  : constant String := "GOLDEN PAVE " & Img (N) & " / " & Img (N_Paves);
               begin
                  Sound.Play (Sound.Chime);
                  if N = N_Paves then
                     Money := Money + 10_000;
                     declare
                        C : constant Car_Ref := Place_Car (Sport, PX, PY, 20.0);
                     begin
                        if C /= 0 then
                           Cars (C).Color := Gold;
                           Cars (C).HP := 400.0;
                        end if;
                     end;
                     Game.Show_Big (Msg, Gold, 4.0, "Every pave found! +10,000 " & World.Meta ("currency", "EUR") & " and a golden car nearby");
                  elsif N = 10 then
                     Game.Show_Big (Msg, Gold, 4.0, "Reward: body armour every time you respawn");
                  elsif N = 20 then
                     Game.Show_Big (Msg, Gold, 4.0, "Reward: the SMG every time you respawn");
                  else
                     Game.Show_Big (Msg, Gold, 2.0);
                  end if;
               end;
            end if;
         end;
      end loop;
   end Update_Paves;

   ------------------------------------------------------------------ pigeons
   procedure Take_Off (B : in out Pigeon; FX, FY : Float) is
      DX : Float := B.X - FX;
      DY : Float := B.Y - FY;
      L  : constant Float := Float'Max (Hypot (DX, DY), 0.01);
      A  : Float;
      S  : constant Float := Rand (5.0, 8.0);
   begin
      DX := DX / L; DY := DY / L;
      A := Arctan (DY, DX) + Rand (-0.7, 0.7);
      B.St := Flying;
      B.VX := Cos (A) * S; B.VY := Sin (A) * S;
      B.VZ := Rand (3.5, 5.5);
      B.A := A;
      B.T := Rand (3.0, 6.0);
   end Take_Off;

   --  every pigeon on the ground within R of (X, Y) flies off, away from (FX, FY)
   procedure Scare_Birds (X, Y, R, FX, FY : Float; By_Player : Boolean) is
      Any : Boolean := False;
   begin
      for B of Birds loop
         if B.Active and then B.St = Ground and then abs (B.X - X) < R and then abs (B.Y - Y) < R
           and then Hypot (B.X - X, B.Y - Y) < R
         then
            Take_Off (B, FX, FY);
            Any := True;
            if By_Player and then not Counted (B.Flock mod 64) then
               Counted (B.Flock mod 64) := True;
               Flocks := Flocks + 1;
               Dirty := True;
               if not Life_Found (Pigeons_Seen) then
                  Life_Found (Pigeons_Seen) := True;
                  Game.Say ("Les pigeons! (Scattered flocks are counted on the pause screen.)", 4.0);
               end if;
            end if;
         end if;
      end loop;
      if Any and then Flutter_Cool <= 0.0 then
         Sound.Play (Sound.Flutter, Float'Max (0.1, 1.0 - Dist (X, Y) / 60.0));
         Flutter_Cool := 0.4;
      end if;
   end Scare_Birds;

   procedure Noise (X, Y, R : Float) is
   begin
      if Player /= 0 then
         Scare_Birds (X, Y, Float'Max (R, 20.0), X, Y, False);
      end if;
   end Noise;

   procedure Spawn_Flock (X, Y : Float) is
      N : constant Natural := 6 + Rand_Int (8);
      K : Natural := 0;
   begin
      Flock_Count := Flock_Count + 1;
      Counted (Flock_Count mod 64) := False;
      for B of Birds loop
         exit when K = N;
         if not B.Active then
            declare
               BX : constant Float := X + Rand (-3.0, 3.0);
               BY : constant Float := Y + Rand (-3.0, 3.0);
            begin
               if not Blocked (BX, BY) then
                  B := (Active => True, St => Ground, X => BX, Y => BY, A => Rand (0.0, 6.28),
                        Hop_T => Rand (0.2, 2.0), Flock => Flock_Count, others => 0.0);
               end if;
               K := K + 1;
            end;
         end if;
      end loop;
   end Spawn_Flock;

   procedure Update_Birds (DT : Float) is
      Alive : Natural := 0;
      Car_Fast : constant Boolean := Player_Car /= 0 and then Speed (Cars (Player_Car)) > 2.0;
      Threat_R : constant Float := (if Player_Car = 0 then 4.5 else (if Car_Fast then 9.0 else 0.0));
   begin
      Flutter_Cool := Flutter_Cool - DT;
      for B of Birds loop
         if B.Active then
            Alive := Alive + 1;
            if Dist (B.X, B.Y) > 190.0 then
               B.Active := False;
            elsif B.St = Ground then
               B.Hop_T := B.Hop_T - DT;
               if B.Hop_T <= 0.0 then
                  B.Hop_T := Rand (0.4, 2.5);
                  B.A := B.A + Rand (-1.2, 1.2);
                  declare
                     NX2 : constant Float := B.X + Cos (B.A) * 0.18;
                     NY2 : constant Float := B.Y + Sin (B.A) * 0.18;
                  begin
                     if not Blocked (NX2, NY2) then
                        B.X := NX2; B.Y := NY2;
                     end if;
                  end;
               end if;
               if Threat_R > 0.0 and then abs (B.X - PX) < Threat_R and then abs (B.Y - PY) < Threat_R
                 and then Dist (B.X, B.Y) < Threat_R
               then
                  Scare_Birds (B.X, B.Y, 6.0, PX, PY, True);
               end if;
            else
               B.X := B.X + B.VX * DT;
               B.Y := B.Y + B.VY * DT;
               B.T := B.T - DT;
               if B.T > 0.0 then
                  B.VZ := (if B.Z > 12.0 then 0.0 else Float'Max (0.8, B.VZ - DT * 1.5));
               else
                  B.VZ := -2.5;
                  B.VX := B.VX * (1.0 - DT * 0.5);
                  B.VY := B.VY * (1.0 - DT * 0.5);
               end if;
               B.Z := B.Z + B.VZ * DT;
               if B.Z <= 0.0 then
                  B.Z := 0.0;
                  if Land (B.X, B.Y) then
                     B.St := Ground; B.VX := 0.0; B.VY := 0.0; B.Hop_T := Rand (0.5, 2.0);
                  else
                     B.T := 2.0; B.VZ := 3.0;      --  can't land on a roof edge or water: go on
                  end if;
               end if;
            end if;
         end if;
      end loop;
      Flock_T := Flock_T - DT;
      if Flock_T <= 0.0 then
         Flock_T := 2.5;
         if Alive < 110 then
            declare
               X, Y : Float;
               Ok   : Boolean;
            begin
               Open_Spot (35.0, 110.0, X, Y, Ok);
               if Ok then
                  Spawn_Flock (X, Y);
               end if;
            end;
         end if;
      end if;
   end Update_Birds;

   ------------------------------------------------------------------ street characters
   function Spawn_Character (Role : Ped_Role; X, Y : Float) return Ped_Ref is
      I : constant Ped_Ref := Alloc_Ped (X, Y);
   begin
      if I /= 0 then
         declare
            P : Ped renames Peds (I);
         begin
            P.Role := Role;
            P.Keep := True;
            P.Mode := Idle;
            P.Walk_Speed := 0.0;
            P.A := Rand (0.0, 6.28);
            if Role = Mime then
               P.Shirt := (0.95, 0.95, 0.95); P.Hair := (0.08, 0.08, 0.1); P.Skin := (0.97, 0.97, 0.97);
            elsif Role = Musician then
               P.Shirt := (0.55, 0.12, 0.14); P.Hair := (0.12, 0.1, 0.1);
            end if;
         end;
      end if;
      return I;
   end Spawn_Character;

   procedure Release (I : in out Ped_Ref) is
   begin
      if I /= 0 then
         if Peds (I).Active then
            Peds (I).Keep := False;
            Peds (I).Role := Citizen;
            Peds (I).Mode := Walk;
            Peds (I).Walk_Speed := 1.3;
            if not Game.On_Screen (Peds (I).X, Peds (I).Y) then
               Peds (I).Active := False;
            end if;
         end if;
         I := 0;
      end if;
   end Release;

   procedure Update_Characters (DT : Float) is
      Music : Float := 0.0;
   begin
      --  the mime: stands still in a square, pretending to be stuck in a box
      if Mime_Ref /= 0 and then (not Peds (Mime_Ref).Active or else Dist (Peds (Mime_Ref).X, Peds (Mime_Ref).Y) > 260.0)
      then
         Release (Mime_Ref);
      end if;
      if Mime_Ref = 0 then
         Mime_T := Mime_T - DT;
         if Mime_T <= 0.0 then
            Mime_T := 45.0;
            declare
               X, Y : Float;
               Ok   : Boolean;
            begin
               Open_Spot (60.0, 150.0, X, Y, Ok, Off_Road => 10.0);
               if Ok then
                  Mime_Ref := Spawn_Character (Mime, X, Y);
               end if;
            end;
         end if;
      elsif not Peds (Mime_Ref).Dead then
         declare
            P : Ped renames Peds (Mime_Ref);
         begin
            P.Moving := False;
            P.Phase := P.Phase + DT * 3.0;
            if On_Foot and then Dist (P.X, P.Y) < 3.5 then
               if Dist (P.X, P.Y) > 0.01 then
                  P.A := Arctan (PY - P.Y, PX - P.X);
               end if;
               if not Life_Found (Mime_Seen) then
                  Life_Found (Mime_Seen) := True;
                  Discover (Title ("mime", "LE MIME"),
                            "He pretends to eat an invisible " & Word (Croissant) & "... then points at the pause button");
               end if;
            end if;
         end;
      end if;

      --  the accordionist: plays a waltz; listen a while to discover
      if Musician_Ref /= 0 and then (not Peds (Musician_Ref).Active or else Peds (Musician_Ref).Dead
                                     or else Peds (Musician_Ref).Role /= Musician
                                     or else Dist (Peds (Musician_Ref).X, Peds (Musician_Ref).Y) > 260.0)
      then
         Release (Musician_Ref);
      end if;
      if Musician_Ref = 0 then
         Musician_T := Musician_T - DT;
         if Musician_T <= 0.0 then
            Musician_T := 50.0;
            declare
               X, Y : Float;
               Ok   : Boolean;
            begin
               Open_Spot (50.0, 140.0, X, Y, Ok, Off_Road => 6.0);
               if Ok then
                  Musician_Ref := Spawn_Character (Musician, X, Y);
               end if;
            end;
         end if;
      else
         declare
            P : Ped renames Peds (Musician_Ref);
            D : constant Float := Dist (P.X, P.Y);
         begin
            P.Moving := False;
            P.Phase := P.Phase + DT * 2.0;
            Music := Float'Max (0.0, 1.0 - D / 45.0) ** 2;
            if On_Foot and then D < 8.0 then
               Listen_T := Listen_T + DT;
               if Listen_T > 3.0 and then not Life_Found (Musician_Seen) then
                  Life_Found (Musician_Seen) := True;
                  Discover (Title ("musician", "L'ACCORDEONISTE"),
                            "He sings of " & Word (Liberte) & "... (type it while the game is paused)");
               end if;
            else
               Listen_T := 0.0;
            end if;
         end;
      end if;
      Sound.Set_Music (if Mode = Play then Music else 0.0);
   end Update_Characters;

   ------------------------------------------------------------------ protest march
   procedure Extend_March is
   begin
      if March.Idx > 40 then
         declare
            Shift : constant Natural := March.Idx - 2;
         begin
            March.Path (1 .. March.Len - Shift) := March.Path (Shift + 1 .. March.Len);
            March.Len := March.Len - Shift;
            March.Idx := March.Idx - Shift;
         end;
      end if;
      while March.Len < March.Path'Last and then March.Len - March.Idx < 10 loop
         declare
            Last : constant Natural := March.Path (March.Len);
            Prev : constant Integer := (if March.Len > 1 then March.Path (March.Len - 1) else -1);
            Deg  : constant Natural := Degree (Car_Graph, Last);
            Next : Natural := Neighbor (Car_Graph, Last, 1);
         begin
            exit when Deg = 0;
            for Try in 1 .. 4 loop
               Next := Neighbor (Car_Graph, Last, 1 + Rand_Int (Deg));
               exit when Next /= Prev;
            end loop;
            March.Len := March.Len + 1;
            March.Path (March.Len) := Next;
         end;
      end loop;
   end Extend_March;

   procedure Start_March (Near : Boolean) is
      N : Integer := -1;
   begin
      if March.Active then
         return;
      end if;
      for Try in 1 .. 30 loop
         declare
            A  : constant Float := Rand (0.0, 2.0 * Pi);
            R  : constant Float := (if Near then Rand (30.0, 70.0) else Rand (140.0, 260.0));
            X  : constant Float := PX + Cos (A) * R;
            Y  : constant Float := PY + Sin (A) * R;
         begin
            N := Nearest (Car_Graph, X, Y, 40.0);
            exit when N >= 0 and then (Near or else not Game.On_Screen (NX (Car_Graph, N), NY (Car_Graph, N), 20.0));
            N := -1;
         end;
      end loop;
      if N < 0 then
         return;
      end if;
      March := (Active => True, Len => 1, Idx => 1, LX => NX (Car_Graph, N), LY => NY (Car_Graph, N),
                others => <>);
      March.Path (1) := N;
      Extend_March;
      for I in 1 .. Max_March loop
         declare
            M : constant Ped_Ref := Alloc_Ped (March.LX + Rand (-3.0, 3.0), March.LY + Rand (-3.0, 3.0));
         begin
            if M /= 0 then
               Peds (M).Role := Marcher;
               Peds (M).Keep := True;
               Peds (M).Mode := Idle;
               March.Members (I) := M;
            end if;
         end;
      end loop;
   end Start_March;

   procedure End_March is
   begin
      for M of March.Members loop
         Release (M);
      end loop;
      March.Active := False;
   end End_March;

   procedure Update_March (DT : Float) is
   begin
      if not March.Active then
         March_T := March_T - DT;
         if March_T <= 0.0 then
            March_T := Rand (180.0, 300.0);
            Start_March (Near => False);
         end if;
         return;
      end if;
      March.T := March.T + DT;
      if March.T > 160.0 or else Dist (March.LX, March.LY) > 420.0 then
         End_March;
         return;
      end if;
      --  the head of the march walks along the road graph
      Extend_March;
      declare
         TX : constant Float := NX (Car_Graph, March.Path (March.Idx));
         TY : constant Float := NY (Car_Graph, March.Path (March.Idx));
         D  : constant Float := Hypot (TX - March.LX, TY - March.LY);
      begin
         if D < 1.2 then
            March.Idx := Natural'Min (March.Idx + 1, March.Len);
         else
            March.DX := March.DX + ((TX - March.LX) / D - March.DX) * Float'Min (1.0, DT * 1.5);
            March.DY := March.DY + ((TY - March.LY) / D - March.DY) * Float'Min (1.0, DT * 1.5);
            March.LX := March.LX + (TX - March.LX) / D * 1.0 * DT;
            March.LY := March.LY + (TY - March.LY) / D * 1.0 * DT;
         end if;
      end;
      declare
         L  : constant Float := Float'Max (Hypot (March.DX, March.DY), 0.01);
         FX : constant Float := March.DX / L;
         FY : constant Float := March.DY / L;
      begin
         for I in March.Members'Range loop
            declare
               M : constant Ped_Ref := March.Members (I);
            begin
               if M /= 0 and then Peds (M).Active and then not Peds (M).Dead and then Peds (M).Role = Marcher then
                  declare
                     P   : Ped renames Peds (M);
                     Row : constant Float := Float ((I - 1) / 4);
                     Col : constant Float := Float ((I - 1) mod 4) - 1.5;
                     Wob : constant Float := Sin (Time * 1.3 + Float (I)) * 0.25;
                     TX  : constant Float := March.LX - FX * (1.0 + Row * 1.4) - FY * (Col * 1.2 + Wob);
                     TY  : constant Float := March.LY - FY * (1.0 + Row * 1.4) + FX * (Col * 1.2 + Wob);
                     DX  : constant Float := TX - P.X;
                     DY  : constant Float := TY - P.Y;
                     D   : constant Float := Hypot (DX, DY);
                     Spd : constant Float := Float'Min (1.8, 0.6 + D * 0.8);
                  begin
                     P.Moving := D > 0.15;
                     if P.Moving then
                        Ped_Move_By (P, DX / D * Float'Min (D, Spd * DT), DY / D * Float'Min (D, Spd * DT));
                        P.A := Arctan (FY, FX);
                     end if;
                     if not Life_Found (Manif_Seen) and then Dist (P.X, P.Y) < 15.0 then
                        Life_Found (Manif_Seen) := True;
                        Discover (Title ("march", "LA MANIF"), "The placards all say " & Word (Greve)
                                  & "! - blend into the crowd to hide from the police");
                     end if;
                  end;
               end if;
            end;
         end loop;
      end;
   end Update_March;

   function Hidden_In_Crowd return Boolean is
      N : Natural := 0;
   begin
      if not March.Active or else not On_Foot then
         return False;
      end if;
      for M of March.Members loop
         if M /= 0 and then Peds (M).Active and then not Peds (M).Dead and then Dist (Peds (M).X, Peds (M).Y) < 3.0
         then
            N := N + 1;
         end if;
      end loop;
      return N >= 3;
   end Hidden_In_Crowd;

   ------------------------------------------------------------------ catacombs
   function Try_Manhole return Boolean is
   begin
      if not On_Foot or else N_Man < 2 or else Fade_T > 0.0 then
         return False;
      end if;
      for I in 1 .. N_Man loop
         if Dist (Manholes (I).X, Manholes (I).Y) < 1.6 then
            Fade_From := I;
            Fade_Max := 1.8;
            Fade_T := Fade_Max;
            Moved := False;
            Sound.Play (Sound.Clang);
            return True;
         end if;
      end loop;
      return False;
   end Try_Manhole;

   procedure Update_Catacombs (DT : Float) is
   begin
      Hint_Cool := Hint_Cool - DT;
      if Fade_T > 0.0 then
         Fade_T := Fade_T - DT;
         Peds (Player).Moving := False;
         if not Moved and then Fade_T < Fade_Max / 2.0 then
            Moved := True;
            declare
               To : constant Positive := Fade_From mod N_Man + 1;
               M  : Manhole renames Manholes (To);
               P  : Ped renames Peds (Player);
            begin
               P.X := M.X + 1.2; P.Y := M.Y;
               if Blocked (P.X, P.Y) then
                  P.X := M.X; P.Y := M.Y;
               end if;
               P.Node := -1;
               Cam_X := P.X; Cam_Y := P.Y;
               if Heat >= 1.0 then
                  Heat := Heat - 1.0;
                  if Heat < 1.0 then
                     Game.Clear_Wanted;
                  end if;
               end if;
               Seen_T := 99.0;
               Sound.Play (Sound.Clang, 0.8);
               declare
                  First : constant Boolean := not Manholes (Fade_From).Used or else not M.Used;
               begin
                  Manholes (Fade_From).Used := True;
                  M.Used := True;
                  Dirty := True;
                  if First then
                     Discover (Title ("catacombs", "LES CATACOMBES"), "You crawl through the bones of " & City & " and climb out at "
                               & To_String (M.Name));
                  else
                     Game.Say ("Through the catacombs to " & To_String (M.Name) & ".", 3.0);
                  end if;
               end;
            end;
         end if;
         return;
      end if;
      if On_Foot and then Hint_Cool <= 0.0 then
         for I in 1 .. N_Man loop
            if Dist (Manholes (I).X, Manholes (I).Y) < 3.0 then
               Game.Say ("A loose manhole cover... press F (or Y) to climb down.", 3.0);
               Hint_Cool := 12.0;
               exit;
            end if;
         end loop;
      end if;
   end Update_Catacombs;

   ------------------------------------------------------------------ secret cars
   procedure Update_Cars (DT : Float) is
   begin
      Respawn_T := Respawn_T - DT;
      for K in Secret_Car loop
         declare
            S : Car_Slot renames Specials (K);
         begin
            if S.Has then
               if Player_Car /= 0 and then Player_Car = S.Ref and then not S.Found then
                  S.Found := True;
                  Dirty := True;
                  declare
                     function Say_It (Default : String) return String is
                       (if Length (S.Text) > 0 then To_String (S.Text) else Default);
                  begin
                  case K is
                     when Escargot =>
                        Discover (Title ("escargot", "L'ESCARGOT"), Say_It ("Slow. Very slow. But almost nothing can stop it"));
                     when Fournil =>
                        Discover (Title ("fournil", "LE FOURNIL"),
                                  Say_It ("It drops fresh bread (health). The radio hums: " & Word (Baguette) & "..."));
                     when Fusee =>
                        Discover (Title ("fusee", "LA FUSEE"), Say_It ("Who parks on the Pont des Arts? Hold on tight"));
                     when Helicopter =>
                        Discover (Title ("helicopter", "L'HELICO"),
                                  Say_It ("Throttle to take off - hold Space / A to land on open ground"));
                     when Plane =>
                        Discover (Title ("plane", "L'AVION"),
                                  Say_It ("Needs a long straight road to take off. The quays are long and straight..."));
                     when Tank =>
                        Discover (Title ("tank", "CHAR D'ASSAUT"),
                                  Say_It ("Borrowed from the army museum.") & " Type " & Word (Char) & " when paused for another");
                  end case;
                  end;
               end if;
               --  bring it back after it was wrecked or taken far away
               if Respawn_T <= 0.0
                 and then (S.Ref = 0 or else not Cars (S.Ref).Active or else Cars (S.Ref).Serial /= S.Serial
                           or else ((Cars (S.Ref).Dead or else Cars (S.Ref).Sunk) and then Player_Car /= S.Ref))
                 and then Dist (S.AX, S.AY) > 220.0
               then
                  if S.Ref /= 0 and then Cars (S.Ref).Active and then Cars (S.Ref).Serial = S.Serial then
                     Cars (S.Ref).Keep := False;
                  end if;
                  Spawn_Special (K);
               end if;
            end if;
         end;
      end loop;
      if Respawn_T <= 0.0 then
         Respawn_T := 5.0;
      end if;
      --  what the special cars do while you drive them
      if Player_Car /= 0 and then not Cars (Player_Car).Dead then
         declare
            C : Car renames Cars (Player_Car);
            L : constant Float := Params (C.Kind).Len / 2.0 + 0.6;
         begin
            if C.Kind = Fournil and then Speed (C) > 3.0 then
               Drop_T := Drop_T - DT;
               if Drop_T <= 0.0 then
                  Drop_T := 2.5;
                  for K of Pickups loop
                     if not K.Active then
                        K := (Active => True, Kind => Health, X => C.X - Cos (C.A) * (L + 1.5),
                              Y => C.Y - Sin (C.A) * (L + 1.5), N => 0, Fixed => False);
                        exit;
                     end if;
                  end loop;
               end if;
            elsif C.Kind = Fusee and then C.Throttle > 0.3 then
               Flame_T := Flame_T - DT;
               if Flame_T <= 0.0 then
                  Flame_T := 0.03;
                  Game.Particle (C.X - Cos (C.A) * L, C.Y - Sin (C.A) * L, Fire);
               end if;
            end if;
         end;
      end if;
   end Update_Cars;

   ------------------------------------------------------------------ cheats
   procedure Paused is
   begin
      for C in Cheat_Id loop
         if Input.Typed_Ends_With (Word (C)) then
            Input.Clear_Typed;
            Mode := Play;
            Sound.Play (Sound.Cheat);
            case C is
               when Croissant =>
                  Peds (Player).HP := 100.0;
                  Armor := 100.0;
                  Game.Show_Big (Word (Croissant), Gold, 2.5, "Fully restored - bon appetit");
               when Liberte =>
                  Game.Clear_Wanted;
                  Game.Show_Big (Word (Liberte), Gold, 2.5, "The police forget all about you");
               when Greve =>
                  Strike_T := 45.0;
                  Start_March (Near => True);
                  Game.Show_Big (Title ("strike", "GREVE GENERALE"), Gold, 3.0, "All traffic stops for 45 seconds");
               when Char =>
                  declare
                     V : constant Car_Ref := Place_Car (Tank, PX, PY, 20.0);
                  begin
                     if V /= 0 then
                        Cars (V).Turret := Cars (V).A;
                     end if;
                     Game.Show_Big (Word (Char), Gold, 2.5, (if V /= 0 then "A tank, just for you" else "No room for a tank here"));
                  end;
               when Baguette =>
                  declare
                     V : constant Car_Ref := Place_Car (Fournil, PX, PY, 16.0);
                  begin
                     Game.Show_Big (Word (Baguette), Gold, 2.5,
                                    (if V /= 0 then "A bakery van, fresh from the oven" else "No room for a van here"));
                  end;
            end case;
            if not Cheat_Found (C) then
               Cheat_Found (C) := True;
               Dirty := True;
            end if;
         end if;
      end loop;
   end Paused;

   ------------------------------------------------------------------ update
   procedure Update (DT : Float) is
   begin
      if Player = 0 or else Mode /= Play then
         Sound.Set_Music (0.0);
         return;
      end if;
      Strike_T := Float'Max (0.0, Strike_T - DT);
      Update_Paves;
      Update_Birds (DT);
      Update_Characters (DT);
      Update_March (DT);
      Update_Catacombs (DT);
      Update_Cars (DT);
      Save_T := Save_T - DT;
      if Dirty and then Save_T <= 0.0 then
         Save;
         Save_T := 1.0;
      end if;
   end Update;

   ------------------------------------------------------------------ drawing
   procedure Draw_Ground (Cr : Cairo_Context) is
      X0 : constant Float := View_X0 - 2.0;
      X1 : constant Float := View_X1 + 2.0;
      Y0 : constant Float := View_Y0 - 2.0;
      Y1 : constant Float := View_Y1 + 2.0;
      function Vis (X, Y : Float) return Boolean is (X > X0 and then X < X1 and then Y > Y0 and then Y < Y1);
   begin
      --  manhole covers
      for I in 1 .. N_Man loop
         declare
            M : Manhole renames Manholes (I);
         begin
            if Vis (M.X, M.Y) then
               Color (Cr, 0.15, 0.15, 0.16);
               Fill_Circle (Cr, M.X, M.Y, 0.72);
               Color (Cr, 0.3, 0.3, 0.32);
               Fill_Circle (Cr, M.X, M.Y, 0.62);
               Color (Cr, 0.18, 0.18, 0.19);
               Width (Cr, 0.07);
               for K in -2 .. 2 loop
                  declare
                     O : constant Float := Float (K) * 0.2;
                     H : constant Float := Sqrt (Float'Max (0.0, 0.55 * 0.55 - O * O));
                  begin
                     Move (Cr, M.X + O, M.Y - H); Line (Cr, M.X + O, M.Y + H);
                     Move (Cr, M.X - H, M.Y + O); Line (Cr, M.X + H, M.Y + O);
                  end;
               end loop;
               Stroke (Cr);
            end if;
         end;
      end loop;
      --  golden paves, with a glint now and then
      for I in 1 .. N_Paves loop
         declare
            P : Pave renames Paves (I);
         begin
            if not P.Found and then Vis (P.X, P.Y) then
               Color (Cr, 1.0, 0.85, 0.3, 0.10 + 0.08 * Sin (Time * 3.0 + Float (I)));
               Fill_Circle (Cr, P.X - 0.02, P.Y - 0.03, 0.75);
               Color (Cr, 0.0, 0.0, 0.0, 0.3);
               Round_Rect (Cr, P.X - 0.24, P.Y - 0.2, 0.55, 0.5, 0.1);
               Fill (Cr);
               Color (Cr, Hex ("#b8860b"));
               Round_Rect (Cr, P.X - 0.3, P.Y - 0.28, 0.56, 0.5, 0.1);
               Fill (Cr);
               Color (Cr, Hex ("#ffd75e"));
               Round_Rect (Cr, P.X - 0.26, P.Y - 0.27, 0.46, 0.38, 0.08);
               Fill (Cr);
               declare
                  G : constant Float := Time * 0.7 + Float (I) * 0.37;
                  F : constant Float := G - Float'Floor (G);
               begin
                  if F < 0.15 then
                     declare
                        S : constant Float := Sin (F / 0.15 * Pi) * 0.6;
                     begin
                        Color (Cr, 1.0, 1.0, 0.9, 0.9);
                        Width (Cr, 0.06);
                        Move (Cr, P.X - S, P.Y - 0.1); Line (Cr, P.X + S, P.Y - 0.1);
                        Move (Cr, P.X, P.Y - 0.1 - S); Line (Cr, P.X, P.Y - 0.1 + S);
                        Stroke (Cr);
                     end;
                  end if;
               end;
            end if;
         end;
      end loop;
      --  pigeons on the ground
      for B of Birds loop
         if B.Active and then B.St = Ground and then Vis (B.X, B.Y) then
            declare
               CA   : constant Float := Cos (B.A);
               SA   : constant Float := Sin (B.A);
               Peck : constant Float := Float'Max (0.0, Sin (Time * 5.0 + B.X * 3.0)) * 0.05;
            begin
               Save (Cr);
               Gfx.Translate (Cr, B.X, B.Y);
               Gfx.Scale (Cr, 1.5);
               Gfx.Translate (Cr, -B.X, -B.Y);
               Color (Cr, 0.0, 0.0, 0.0, 0.25);
               Ellipse (Cr, B.X + 0.05, B.Y + 0.06, 0.17, 0.1, B.A);
               Fill (Cr);
               Color (Cr, 0.36, 0.38, 0.43);
               Ellipse (Cr, B.X - CA * 0.12, B.Y - SA * 0.12, 0.1, 0.07, B.A);
               Fill (Cr);
               Color (Cr, 0.55, 0.57, 0.63);
               Ellipse (Cr, B.X, B.Y, 0.16, 0.095, B.A);
               Fill (Cr);
               Color (Cr, 0.35, 0.5, 0.42);
               Fill_Circle (Cr, B.X + CA * (0.12 + Peck), B.Y + SA * (0.12 + Peck), 0.055);
               Color (Cr, 0.3, 0.3, 0.36);
               Fill_Circle (Cr, B.X + CA * (0.18 + Peck), B.Y + SA * (0.18 + Peck), 0.05);
               Restore (Cr);
            end;
         end if;
      end loop;
   end Draw_Ground;

   procedure Draw_Air (Cr : Cairo_Context; Cam_X, Cam_Y, Cam_H : Float) is
   begin
      for B of Birds loop
         if B.Active and then B.St = Flying and then B.X > View_X0 - 20.0 and then B.X < View_X1 + 20.0
           and then B.Y > View_Y0 - 20.0 and then B.Y < View_Y1 + 20.0
         then
            declare
               K    : constant Float := B.Z / Float'Max (Cam_H - B.Z, 20.0);
               X    : constant Float := B.X + (B.X - Cam_X) * K;
               Y    : constant Float := B.Y + (B.Y - Cam_Y) * K;
               S    : constant Float := 1.5 * (1.0 + K * 1.5);
               Flap : constant Float := Sin (Time * 24.0 + B.X * 7.0);
               CA   : constant Float := Cos (B.A);
               SA   : constant Float := Sin (B.A);
               WS   : constant Float := (0.18 + 0.2 * abs Flap) * S;
            begin
               Color (Cr, 0.0, 0.0, 0.0, Float'Max (0.0, 0.22 - B.Z * 0.012));
               Ellipse (Cr, B.X + B.Z * 0.15, B.Y + B.Z * 0.2, 0.18, 0.1, B.A);
               Fill (Cr);
               Color (Cr, 0.5, 0.52, 0.58);
               --  wings: two ellipses either side of the body
               Ellipse (Cr, X - SA * WS, Y + CA * WS, 0.07 * S, WS, B.A);
               Ellipse (Cr, X + SA * WS, Y - CA * WS, 0.07 * S, WS, B.A);
               Fill (Cr);
               Color (Cr, 0.58, 0.6, 0.66);
               Ellipse (Cr, X, Y, 0.17 * S, 0.08 * S, B.A);
               Fill (Cr);
               Color (Cr, 0.3, 0.3, 0.36);
               Fill_Circle (Cr, X + CA * 0.17 * S, Y + SA * 0.17 * S, 0.05 * S);
            end;
         end if;
      end loop;
   end Draw_Air;

   procedure Draw_Overlay (Cr : Cairo_Context) is
   begin
      if Fade_T > 0.0 then
         declare
            H : constant Float := Fade_Max / 2.0;
            A : constant Float := 1.0 - abs (Fade_T - H) / H;
         begin
            Color (Cr, 0.0, 0.0, 0.0, Float'Min (1.0, A * 1.3));
            Fill_Rect (Cr, 0.0, 0.0, Screen_W, Screen_H);
         end;
      end if;
   end Draw_Overlay;

   procedure Draw_Journal (Cr : Cairo_Context; X, Y, S : Float) is
      Line_H : constant Float := 24.0 * S;
      Row    : Float := Y;
      Lbl    : constant RGB := Gold;
      Val    : constant RGB := (0.93, 0.93, 0.93);
      Dim    : constant RGB := (0.6, 0.6, 0.6);
      procedure Put (Label, Value : String; Dimmed : Boolean := False) is
      begin
         Text (Cr, Label, X - 12.0 * S, Row, 16.0 * S, Lbl, Right, Outline => 0.0);
         Text (Cr, Value, X + 12.0 * S, Row, 16.0 * S, (if Dimmed then Dim else Val), Left,
               Bold => False, Outline => 0.0);
         Row := Row + Line_H;
      end Put;
      function Name_Or (Found : Boolean; Name : String) return String is (if Found then Name else "???");
      Cars_S, Life_S, Cheat_S : Unbounded_String;
      Holes_Used : Natural := 0;
      Found      : constant Natural := Found_Paves;
   begin
      Text (Cr, "DISCOVERIES", X, Row, 22.0 * S, Lbl, Center, Outline => 0.0);
      Row := Row + 34.0 * S;
      Put ("Golden paves", Img (Found) & " / " & Img (N_Paves)
           & (if Found >= N_Paves then "   - all found!"
              elsif Found < 10 then "   (" & Img (10 - Found) & " more: armour on respawn)"
              elsif Found < 20 then "   (" & Img (Natural'Min (20, N_Paves) - Found)
                 & " more: " & (if N_Paves > 20 then "SMG on respawn)" else "the golden car)")
              else "   (" & Img (N_Paves - Found) & " more: the golden car)"));
      for K in Secret_Car loop
         if Specials (K).Has then
            Append (Cars_S, (if Length (Cars_S) > 0 then "  -  " else "")
                    & Name_Or (Specials (K).Found, To_String (Car_Names (K))));
         end if;
      end loop;
      Put ("Secret vehicles", To_String (Cars_S));
      for I in 1 .. N_Man loop
         if Manholes (I).Used then
            Holes_Used := Holes_Used + 1;
         end if;
      end loop;
      if N_Man >= 2 then
         Put ("Catacombs", Img (Holes_Used) & " / " & Img (N_Man) & " manholes used");
      end if;
      for L in Life_Id loop
         Append (Life_S, (if Length (Life_S) > 0 then "  -  " else "")
                 & Name_Or (Life_Found (L), To_String (Life_Name (L))));
      end loop;
      Put ("Street life", To_String (Life_S));
      Put ("Pigeon flocks", Img (Flocks) & " scattered");
      for C in Cheat_Id loop
         Append (Cheat_S, (if Length (Cheat_S) > 0 then "  -  " else "")
                 & Name_Or (Cheat_Found (C), Word (C)));
      end loop;
      Put ("Cheat words", To_String (Cheat_S));
      Row := Row + 6.0 * S;
      Text (Cr, "Street life drops hints. Type a cheat word while the game is paused.",
            X, Row, 13.0 * S, Dim, Center, Bold => False, Outline => 0.0);
   end Draw_Journal;

   ------------------------------------------------------------------ self test
   procedure Self_Test is
      use Ada.Text_IO;
      procedure Run (Sec : Float) is
      begin
         for I in 1 .. Integer (Sec * 60.0) loop
            Game.Frame (1.0 / 60.0);
         end loop;
      end Run;
      procedure Check (Name : String; Ok : Boolean) is
      begin
         Put_Line ((if Ok then "ok   " else "FAIL ") & Name);
      end Check;
   begin
      Persist := False;
      Game.Start_Game;
      Run (0.5);
      Put_Line ("paves" & N_Paves'Image & ", manholes" & N_Man'Image);
      for K in Secret_Car loop
         Put_Line ("secret car " & Car_Type'Image (K) & ": anchor " & Boolean'Image (Specials (K).Has)
                   & ", placed " & Boolean'Image (Specials (K).Ref /= 0));
      end loop;
      --  a golden pave
      Peds (Player).X := Paves (1).X + 3.0; Peds (Player).Y := Paves (1).Y;
      Run (1.0);
      if Shot /= null then
         Shot ("pave");
      end if;
      Peds (Player).X := Paves (1).X; Peds (Player).Y := Paves (1).Y;
      Run (0.2);
      Check ("pick up a golden pave", Found_Paves = 1);
      --  catacombs
      if N_Man >= 2 then
         Heat := 2.5;
         Peds (Player).X := Manholes (1).X; Peds (Player).Y := Manholes (1).Y;
         Input.Hit (Input.K_F) := True;
         Run (0.7);
         if Shot /= null then
            Shot ("catacombs");
         end if;
         Run (1.8);
         Check ("catacombs: manhole 1 -> 2", Dist (Manholes (2).X, Manholes (2).Y) < 3.0);
         Check ("catacombs: one star less", Game.Stars = 1);
      end if;
      --  a secret car
      for K in Secret_Car loop
         if Specials (K).Ref /= 0 then
            declare
               C : Car renames Cars (Specials (K).Ref);
            begin
               Peds (Player).X := C.X + Cos (C.A + Pi / 2.0) * 2.0;
               Peds (Player).Y := C.Y + Sin (C.A + Pi / 2.0) * 2.0;
               Run (0.1);
               Gamepad.Hit (Gamepad.Y) := True;
               Run (0.3);
               Check ("drive the secret car " & Car_Type'Image (K), Specials (K).Found);
               if Shot /= null then
                  Shot ("secret_car");
               end if;
               Gamepad.Hit (Gamepad.Y) := True;
               Run (0.3);
            end;
            exit;
         end if;
      end loop;
      --  cheat words
      Heat := 3.5; Seen_T := 0.0;
      State.Mode := Paused;
      Input.Typed := (others => 'x');
      Input.Typed (Input.Typed'Last - Word (Liberte)'Length + 1 .. Input.Typed'Last) := Word (Liberte);
      Paused;
      Check ("cheat " & Word (Liberte) & " clears the wanted level", Game.Stars = 0 and then State.Mode = Play);
      State.Mode := Paused;
      Input.Typed := (others => 'x');
      Input.Typed (Input.Typed'Last - Word (Greve)'Length + 1 .. Input.Typed'Last) := Word (Greve);
      Paused;
      Check ("cheat " & Word (Greve) & " starts a strike and a march", Strike and then March.Active);
      Run (8.0);
      if Shot /= null and then March.Members (1) /= 0 then
         Peds (Player).X := Peds (March.Members (1)).X + 12.0; Peds (Player).Y := Peds (March.Members (1)).Y;
         Run (1.5);
         Shot ("march");
      end if;
      --  the march: walk into it
      declare
         M : constant Ped_Ref := March.Members (6);
      begin
         if M /= 0 then
            Peds (Player).X := Peds (M).X + 0.5; Peds (Player).Y := Peds (M).Y;
            Run (0.1);
            Check ("hidden in the march", Hidden_In_Crowd);
            Check ("march discovered", Life_Found (Manif_Seen));
         end if;
      end;
      --  pigeons (end the strike first: honking jammed cars would scare them off)
      End_March;
      Strike_T := 0.0;
      declare
         X, Y : Float;
         Ok   : Boolean;
      begin
         Open_Spot (20.0, 60.0, X, Y, Ok, Visible_Ok => True);
         if Ok then
            Spawn_Flock (X, Y);
            if Shot /= null then
               Peds (Player).X := X + 9.0; Peds (Player).Y := Y;
               Run (1.0);
               Shot ("pigeons_ground");
            end if;
            Peds (Player).X := X + 1.0; Peds (Player).Y := Y;
            Run (0.6);
            if Shot /= null then
               Shot ("pigeons_flying");
            end if;
            Check ("pigeons scatter", Flocks >= 1);
         end if;
      end;
      --  the mime and the accordionist
      declare
         X, Y : Float;
         Ok   : Boolean;
      begin
         Open_Spot (20.0, 80.0, X, Y, Ok, Visible_Ok => True, Off_Road => 4.0);
         if Ok then
            Release (Mime_Ref);
            Mime_Ref := Spawn_Character (Mime, X, Y);
            Peds (Player).X := X + 1.5; Peds (Player).Y := Y;
            Run (0.2);
            Check ("meet the mime", Life_Found (Mime_Seen));
            Release (Musician_Ref);
            Musician_Ref := Spawn_Character (Musician, X + 4.0, Y);
            Peds (Player).X := X + 5.0; Peds (Player).Y := Y;
            Run (3.5);
            Check ("listen to the accordionist", Life_Found (Musician_Seen));
            if Shot /= null then
               Shot ("mime_musician");
            end if;
            State.Mode := Paused;
            if Shot /= null then
               Shot ("journal");
            end if;
            State.Mode := Play;
         end if;
      end;
      if Shot /= null and then Specials (Fusee).Ref /= 0 then
         Peds (Player).X := Cars (Specials (Fusee).Ref).X + 6.0; Peds (Player).Y := Cars (Specials (Fusee).Ref).Y;
         Run (1.5);
         Shot ("fusee");
         if Specials (Fournil).Ref /= 0 then
            Peds (Player).X := Cars (Specials (Fournil).Ref).X + 6.0; Peds (Player).Y := Cars (Specials (Fournil).Ref).Y;
            Run (1.5);
            Shot ("fournil");
         end if;
      end if;
   end Self_Test;

end Secrets;
