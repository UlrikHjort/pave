-- ***************************************************************************
--                      PAVÉ - Game
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

with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Strings.Unbounded;   use Ada.Strings.Unbounded;
with Util;    use Util;
with State;   use State;
with World;   use World;
with Physics; use Physics;
with Input;   use Input;
with Gamepad;
with Sound;
with Secrets;
use type Secrets.Shot_Proc;
with Ada.Text_IO;

package body Game is

   --  city settings (Paris unless the map says otherwise)
   function City return String is (World.Meta ("city", "Paris"));
   function Cur return String is (World.Meta ("currency", "EUR"));

   function Euro (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Euro;

   ------------------------------------------------------------------ messages
   procedure Say (S : String; Dur : Float := 4.0) is
   begin
      Message := To_Unbounded_String (S);
      Msg_T := Dur;
   end Say;

   procedure Show_Big (S : String; C : RGB; Dur : Float := 2.5; Sub : String := "") is
   begin
      Big_Text := To_Unbounded_String (S);
      Big_Sub := To_Unbounded_String (Sub);
      Big_Color := C;
      Big_T := Dur;
      Big_Max := Dur;
   end Show_Big;

   Yellow : constant RGB := (1.0, 0.82, 0.29);
   Red    : constant RGB := (0.88, 0.19, 0.19);
   Green  : constant RGB := (0.29, 0.89, 0.42);
   Blue   : constant RGB := (0.29, 0.64, 1.0);

   function Stars return Natural is (Natural'Min (5, Natural (Float'Floor (Heat))));

   function PX return Float is (Peds (Player).X);
   function PY return Float is (Peds (Player).Y);

   --  volume falloff with distance from the player
   function Att (X, Y : Float; Range_M : Float := 140.0) return Float is
     (Clamp (1.0 - Hypot (X - PX, Y - PY) / Range_M, 0.0, 1.0));

   ------------------------------------------------------------------ effects
   procedure Particle (X, Y : Float; K : Part_Kind) is
      A : constant Float := Rand (0.0, 6.28);
      S, Life, SP, Drag : Float;
      Top : Boolean := False;
   begin
      case K is
         when Smoke      => S := Rand (0.5, 1.5); Life := Rand (1.5, 2.5); SP := Rand (0.3, 1.2); Drag := 0.5; Top := True;
         when Fire       => S := Rand (0.4, 1.0); Life := Rand (0.4, 0.9); SP := Rand (0.5, 2.0); Drag := 1.0; Top := True;
         when Boom       => S := Rand (1.5, 3.5); Life := Rand (0.5, 0.9); SP := Rand (2.0, 9.0); Drag := 3.0; Top := True;
         when Spark      => S := 0.12; Life := Rand (0.15, 0.35); SP := Rand (4.0, 10.0); Drag := 4.0;
         when Blood_Drop => S := Rand (0.1, 0.25); Life := Rand (0.3, 0.6); SP := Rand (1.0, 4.0); Drag := 4.0;
         when Debris     => S := Rand (0.15, 0.35); Life := Rand (0.8, 1.5); SP := Rand (4.0, 14.0); Drag := 2.5;
         when Flash      => S := 0.5; Life := 0.05; SP := 0.0; Drag := 0.0;
         when Splash     => S := Rand (0.3, 0.8); Life := Rand (0.4, 0.8); SP := Rand (0.5, 2.0); Drag := 1.0;
      end case;
      for I in Parts'Range loop
         if not Parts (I).Active then
            Parts (I) := (True, K, X, Y, Cos (A) * SP, Sin (A) * SP, Life, Life, S, Drag, Top);
            return;
         end if;
      end loop;
   end Particle;

   procedure Add_Blood (X, Y : Float) is
   begin
      Blood (Blood_Head) := (X, Y, Rand (0.6, 1.1), Rand (0.0, 6.0));
      Blood_Head := (Blood_Head + 1) mod Max_Blood;
      Blood_Count := Natural'Min (Blood_Count + 1, Max_Blood);
   end Add_Blood;

   procedure Add_Scorch (X, Y : Float) is
   begin
      Scorch (Scorch_Head) := (X, Y, Rand (3.0, 4.5), 0.0);
      Scorch_Head := (Scorch_Head + 1) mod Max_Scorch;
      Scorch_Count := Natural'Min (Scorch_Count + 1, Max_Scorch);
   end Add_Scorch;

   procedure Add_Tracer (X0, Y0, X1, Y1 : Float) is
   begin
      for T of Tracers loop
         if T.Life <= 0.0 then
            T := (X0, Y0, X1, Y1, 0.06);
            return;
         end if;
      end loop;
   end Add_Tracer;

   procedure Add_Skid (C : in out Car) is
      P  : Car_Params renames Params (C.Kind);
      FX : constant Float := Cos (C.A);
      FY : constant Float := Sin (C.A);
      BX : constant Float := C.X - FX * P.Len * 0.35;
      BY : constant Float := C.Y - FY * P.Len * 0.35;
      W2 : constant Float := P.Wid * 0.4;
      N  : constant Float_Array (0 .. 3) := (BX - FY * W2, BY + FX * W2, BX + FY * W2, BY - FX * W2);
   begin
      if C.Has_Skid then
         Skids (Skid_Head) := (C.Skid (0), C.Skid (1), N (0), N (1));
         Skid_Head := (Skid_Head + 1) mod Max_Skids;
         Skids (Skid_Head) := (C.Skid (2), C.Skid (3), N (2), N (3));
         Skid_Head := (Skid_Head + 1) mod Max_Skids;
         Skid_Count := Natural'Min (Skid_Count + 2, Max_Skids);
      end if;
      C.Skid := N;
      C.Has_Skid := True;
   end Add_Skid;

   ------------------------------------------------------------------ view helpers
   function On_Screen (X, Y : Float; M : Float := 8.0) return Boolean is
     (X > View_X0 - M and then X < View_X1 + M and then Y > View_Y0 - M and then Y < View_Y1 + M);

   procedure Screen_To_World (SX, SY : Float; WX, WY : out Float) is
   begin
      WX := (SX - Screen_W / 2.0) / Cam_Z + Cam_X;
      WY := (SY - Screen_H / 2.0) / Cam_Z + Cam_Y;
   end Screen_To_World;

   ------------------------------------------------------------------ wanted level
   procedure Add_Heat (N : Float; Seen : Boolean := False) is
      Before : constant Natural := Stars;
   begin
      if Mode /= Play then
         return;
      end if;
      Heat := Float'Min (5.99, Heat + N);
      if Seen then
         Seen_T := 0.0;
      end if;
      if Stars > Before then
         Star_Flash := 1.5;
      end if;
   end Add_Heat;

   procedure Become_Traffic (CI : Car_Ref);

   procedure Clear_Wanted is
   begin
      Heat := 0.0;
      Seen_T := 99.0;
      Bust_T := 0.0;
      for I in Cars'Range loop
         if Cars (I).Active and then Cars (I).Driver = AI_Driver and then Cars (I).AI.Mode = Pursuit then
            Become_Traffic (I);
         end if;
      end loop;
   end Clear_Wanted;

      function Cops_Near (X, Y, R : Float) return Boolean is
   begin
      for C of Cars loop
         if C.Active and then C.Kind = Police and then not C.Dead and then C.Driver /= No_Driver
           and then Hypot (C.X - X, C.Y - Y) < R
         then
            return True;
         end if;
      end loop;
      for P of Peds loop
         if P.Active and then P.Cop and then not P.Dead and then Hypot (P.X - X, P.Y - Y) < R then
            return True;
         end if;
      end loop;
      return False;
   end Cops_Near;

   procedure Scare_Around (X, Y, R, T : Float) is
   begin
      Secrets.Noise (X, Y, R);
      for P of Peds loop
         if P.Active and then not P.Dead and then (P.X - X) ** 2 + (P.Y - Y) ** 2 < R * R then
            Ped_Scare (P, X, Y, T);
         end if;
      end loop;
   end Scare_Around;

   ------------------------------------------------------------------ missions (forward)
   procedure Fail_Mission (Why : String);

   ------------------------------------------------------------------ death / arrest
   procedure Die (Text, Sub : String) is
      Fee : constant Integer := Integer'Min (Money, 1000);
   begin
      if Mode /= Play then
         return;
      end if;
      Mode := Dead; Dead_T := 3.5; Busted := False;
      Sound.Play (Sound.Job_Failed);
      Money := Money - Fee;
      Show_Big (Text, Red, 3.5,
                (if Sub /= "" then Sub elsif Fee > 0 then "Hospital bill: " & Euro (Fee) & " " & Cur else ""));
      if Player_Car = 0 then
         Peds (Player).Dead := True;
      end if;
      Fail_Mission ("");
   end Die;

   procedure Arrest is
      Fine : constant Integer := Integer'Min (Money, 500 + Stars * 500);
   begin
      if Mode /= Play then
         return;
      end if;
      Mode := Dead; Dead_T := 3.5; Busted := True;
      Sound.Play (Sound.Job_Failed);
      Money := Money - Fine;
      Show_Big ("BUSTED", Blue, 3.5, (if Fine > 0 then "Fine: " & Euro (Fine) & " " & Cur else ""));
      Fail_Mission ("");
   end Arrest;

   ------------------------------------------------------------------ peds: damage
   procedure Kill_Ped (I : Ped_Ref; By : Culprit) is
      P : Ped renames Peds (I);
   begin
      if P.Dead then
         return;
      end if;
      P.Dead := True; P.HP := 0.0; P.Dead_T := 0.0;
      Sound.Play (Sound.Splat, Att (P.X, P.Y, 80.0));
      Add_Blood (P.X, P.Y);
      Scare_Around (P.X, P.Y, 25.0, 8.0);
      if By = By_Player then
         Add_Heat ((if P.Cop then 1.5 else 0.7), True);
         if Rand < 0.6 then
            for K of Pickups loop
               if not K.Active then
                  K := (True, Cash, P.X + Rand (-0.5, 0.5), P.Y + Rand (-0.5, 0.5), 10 + Rand_Int (60), False);
                  exit;
               end if;
            end loop;
         end if;
      end if;
      if Has_Mission and then Mis.M_Target = I then
         Mis.Target_Dead := True;
      end if;
   end Kill_Ped;

   procedure Hurt_Ped (I : Ped_Ref; Dmg : Float; By : Culprit; DX, DY : Float := 0.0) is
      P : Ped renames Peds (I);
      D : Float := Dmg;
   begin
      if P.Dead then
         return;
      end if;
      if P.Is_Player then
         if Mode /= Play then
            return;
         end if;
         if Armor > 0.0 then
            declare
               A : constant Float := Float'Min (Armor, D * 0.7);
            begin
               Armor := Armor - A;
               D := D - A;
            end;
         end if;
         P.HP := P.HP - D;
         Hurt_Flash := 0.3;
         if P.HP <= 0.0 then
            P.HP := 0.0;
            Die ("WASTED", "");
         end if;
         return;
      end if;
      P.HP := P.HP - D;
      if P.Cop and then By = By_Player then
         Add_Heat (0.5, True);
      end if;
      P.X := P.X + DX * 0.4;
      P.Y := P.Y + DY * 0.4;
      for K in 1 .. 3 loop
         Particle (P.X, P.Y, Blood_Drop);
      end loop;
      if P.HP <= 0.0 then
         Kill_Ped (I, By);
      elsif not P.Cop then
         Ped_Scare (P, P.X - DX, P.Y - DY, 8.0);
      end if;
   end Hurt_Ped;

   ------------------------------------------------------------------ explosions
   procedure Explode (CI : Car_Ref) is
      C          : Car renames Cars (CI);
      Was_Player : constant Boolean := Player_Car = CI;
      By         : Culprit := C.Last_Hit;
   begin
      if By = Nobody and then C.Driver = Player_Driver then
         By := By_Player;
      end if;
      C.Dead := True; C.Fire_T := 0.0; C.HP := 0.0; C.Siren := False;
      if Is_Boat (C.Kind) then          --  a wrecked boat goes down
         C.Sunk := True;
         C.Sink_T := 0.0;
      end if;
      if C.Driver = AI_Driver then
         C.Driver := No_Driver;
      end if;
      Shake := Float'Max (Shake, 1.2 - Float'Min (1.0, Hypot (C.X - PX, C.Y - PY) / 120.0));
      Sound.Play (Sound.Explosion, Float'Max (0.15, Att (C.X, C.Y, 260.0)));
      for K in 1 .. 30 loop
         Particle (C.X + Rand (-1.5, 1.5), C.Y + Rand (-1.5, 1.5), (if K <= 12 then Boom else Fire));
      end loop;
      for K in 1 .. 14 loop
         Particle (C.X, C.Y, Debris);
      end loop;
      Add_Scorch (C.X, C.Y);
      for I in Peds'Range loop
         declare
            P : Ped renames Peds (I);
         begin
            if P.Active and then not P.Dead and then not (P.Is_Player and then Player_Car /= 0) then
               declare
                  D : constant Float := Hypot (P.X - C.X, P.Y - C.Y);
                  N : constant Float := Float'Max (D, 0.01);
               begin
                  if D < 6.0 then
                     Hurt_Ped (I, (if P.Is_Player then 90.0 * (1.0 - D / 6.0) else 200.0),
                               (if By = By_Player then By_Player else By_NPC),
                               (P.X - C.X) / N, (P.Y - C.Y) / N);
                  elsif D < 40.0 then
                     Ped_Scare (P, C.X, C.Y, 8.0);
                  end if;
               end;
            end if;
         end;
      end loop;
      for J in Cars'Range loop
         declare
            O : Car renames Cars (J);
         begin
            if J /= CI and then O.Active and then not O.Dead then
               declare
                  D : constant Float := Float'Max (Hypot (O.X - C.X, O.Y - C.Y), 0.01);
               begin
                  if D < 7.0 then
                     Damage (O, 70.0 * (1.0 - D / 7.0), By);
                     O.VX := O.VX + (O.X - C.X) / D * 6.0;
                     O.VY := O.VY + (O.Y - C.Y) / D * 6.0;
                  end if;
               end;
            end if;
         end;
      end loop;
      C.VX := C.VX * 0.3; C.VY := C.VY * 0.3;
      if Was_Player then
         Die ("WASTED", "");
      end if;
      if Has_Mission and then Mis.M_Car = CI then
         Mis.Car_Lost := True;
      end if;
   end Explode;

   procedure On_Crash (CI : Car_Ref; V : Float; X, Y : Float) is
   begin
      if V > 6.0 then
         Sound.Play (Sound.Crash, Float'Min (1.0, V / 25.0) * (if CI = Player_Car then 1.0 else Att (X, Y, 60.0)));
      end if;
      if V > 9.0 then
         for K in 1 .. 4 loop
            Particle (X, Y, Spark);
         end loop;
      end if;
      if CI = Player_Car and then V > 10.0 then
         Shake := Float'Max (Shake, Float'Min (0.8, V / 30.0));
      end if;
   end On_Crash;

   ------------------------------------------------------------------ shooting
   --  one bullet or pellet: a ray that stops at the first wall, car or person
   procedure Fire_Ray (Shooter : Ped_Ref; X, Y, Angle : Float; W : Natural; From_Car : Car_Ref) is
      WI     : Weapon_Info renames Weapons (W);
      Is_P   : constant Boolean := Shooter = Player;
      S      : Ped renames Peds (Shooter);
      Ang    : constant Float := Angle + Rand (-WI.Spread, WI.Spread) * (if S.Cop then 3.0 else 1.0);
      Who    : constant Culprit := (if Is_P then By_Player elsif S.Cop then By_Cop else By_NPC);
   begin
      declare
         DX : constant Float := Cos (Ang);
         DY : constant Float := Sin (Ang);
         Cand_P : array (1 .. 64) of Ped_Ref;
         Cand_C : array (1 .. 32) of Car_Ref;
         NP, NC : Natural := 0;
         T      : Float := 0.2;
         Hit_P  : Ped_Ref := 0;
         Hit_C  : Car_Ref := 0;
      begin
         Particle (X + DX * 0.3, Y + DY * 0.3, Flash);
         for I in Peds'Range loop
            declare
               P : Ped renames Peds (I);
            begin
               if I /= Shooter and then P.Active and then not P.Dead
                 and then not (P.Is_Player and then Player_Car /= 0) and then NP < Cand_P'Last
               then
                  declare
                     RX    : constant Float := P.X - X;
                     RY    : constant Float := P.Y - Y;
                     Along : constant Float := RX * DX + RY * DY;
                  begin
                     if Along > -1.0 and then Along < WI.Rng and then abs (RX * DY - RY * DX) < 0.6 then
                        NP := NP + 1;
                        Cand_P (NP) := I;
                     end if;
                  end;
               end if;
            end;
         end loop;
         for I in Cars'Range loop
            declare
               C : Car renames Cars (I);
            begin
               if I /= From_Car and then C.Active and then not C.Sunk and then NC < Cand_C'Last then
                  declare
                     RX    : constant Float := C.X - X;
                     RY    : constant Float := C.Y - Y;
                     Along : constant Float := RX * DX + RY * DY;
                  begin
                     if Along > -3.0 and then Along < WI.Rng + 3.0
                       and then abs (RX * DY - RY * DX) < Params (C.Kind).Len / 2.0 + 0.5
                     then
                        NC := NC + 1;
                        Cand_C (NC) := I;
                     end if;
                  end;
               end if;
            end;
         end loop;
         Ray :
         while T < WI.Rng loop
            declare
               QX : constant Float := X + DX * T;
               QY : constant Float := Y + DY * T;
            begin
               if World.Solid (QX, QY) then
                  Particle (QX, QY, Spark);
                  Particle (QX, QY, Spark);
                  exit Ray;
               end if;
               for K in 1 .. NC loop
                  declare
                     C  : Car renames Cars (Cand_C (K));
                     EX : constant Float := QX - C.X;
                     EY : constant Float := QY - C.Y;
                     FX : constant Float := Cos (C.A);
                     FY : constant Float := Sin (C.A);
                  begin
                     if abs (EX * FX + EY * FY) < Params (C.Kind).Len / 2.0
                       and then abs (-EX * FY + EY * FX) < Params (C.Kind).Wid / 2.0
                     then
                        Hit_C := Cand_C (K);
                        exit Ray;
                     end if;
                  end;
               end loop;
               for K in 1 .. NP loop
                  if (QX - Peds (Cand_P (K)).X) ** 2 + (QY - Peds (Cand_P (K)).Y) ** 2 < 0.16 then
                     Hit_P := Cand_P (K);
                     exit Ray;
                  end if;
               end loop;
            end;
            T := T + 0.25;
         end loop Ray;
         Add_Tracer (X, Y, X + DX * T, Y + DY * T);
         if Hit_C /= 0 then
            Damage (Cars (Hit_C), WI.Dmg * 0.25, Who);
            Particle (X + DX * T, Y + DY * T, Spark);
            if Is_P and then Cars (Hit_C).Kind = Police then
               Add_Heat (0.25, True);
            end if;
            if Cars (Hit_C).Driver = AI_Driver and then Cars (Hit_C).Kind /= Police then
               Cars (Hit_C).AI.Panic := 8.0;
            end if;
         elsif Hit_P /= 0 then
            Hurt_Ped (Hit_P, WI.Dmg, Who, DX, DY);
         end if;
      end;
   end Fire_Ray;

   ------------------------------------------------------------------ explosives
   --  an explosion at (X, Y): hurts people, damages (and chains) cars, scorches the ground
   procedure Blast (X, Y, R, Power : Float; By : Culprit) is
   begin
      Shake := Float'Max (Shake, 1.1 - Float'Min (1.0, Hypot (X - PX, Y - PY) / 140.0));
      Sound.Play (Sound.Explosion, Float'Max (0.15, Att (X, Y, 260.0)));
      for K in 1 .. 20 loop
         Particle (X + Rand (-1.2, 1.2), Y + Rand (-1.2, 1.2), (if K <= 9 then Boom else Fire));
      end loop;
      for K in 1 .. 8 loop
         Particle (X, Y, Debris);
      end loop;
      Add_Scorch (X, Y);
      for I in Peds'Range loop
         declare
            P : Ped renames Peds (I);
         begin
            if P.Active and then not P.Dead and then not (P.Is_Player and then Player_Car /= 0) then
               declare
                  D : constant Float := Hypot (P.X - X, P.Y - Y);
                  N : constant Float := Float'Max (D, 0.01);
               begin
                  if D < R then
                     Hurt_Ped (I, Power * (1.0 - D / R) * (if P.Is_Player then 0.55 else 1.6), By,
                               (P.X - X) / N, (P.Y - Y) / N);
                  elsif D < R * 6.0 then
                     Ped_Scare (P, X, Y, 8.0);
                  end if;
               end;
            end if;
         end;
      end loop;
      for J in Cars'Range loop
         declare
            O : Car renames Cars (J);
         begin
            if O.Active and then not O.Dead then
               declare
                  Reach : constant Float := R + Params (O.Kind).Len / 2.0;
                  D     : constant Float := Float'Max (Hypot (O.X - X, O.Y - Y), 0.01);
               begin
                  if D < Reach then
                     Damage (O, Power * 1.4 * (1.0 - D / Reach), By);
                     O.VX := O.VX + (O.X - X) / D * 8.0 / Params (O.Kind).Mass;
                     O.VY := O.VY + (O.Y - Y) / D * 8.0 / Params (O.Kind).Mass;
                     if O.HP <= 0.0 then
                        O.Fire_T := Float'Min (O.Fire_T, 0.5);     --  chain reaction
                     end if;
                     if O.Driver = AI_Driver and then O.AI.Mode = Traffic then
                        O.AI.Panic := 8.0;
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;
      Scare_Around (X, Y, 60.0, 8.0);
      if By = By_Player then
         Add_Heat (0.8, Cops_Near (X, Y, 60.0));
      end if;
   end Blast;

   procedure Launch (K : Proj_Kind; X, Y, Ang : Float; By : Culprit; Owner_Ped : Ped_Ref;
                     Owner_Car : Car_Ref; Dist : Float := 12.0) is
      Drop_Z : constant Float := (if Owner_Car /= 0 then Cars (Owner_Car).Z else 0.0);
   begin
      for Q of Projs loop
         if not Q.Active then
            Q := (Active => True, Kind => K, X => X, Y => Y, By => By, Owner_Ped => Owner_Ped,
                  Owner_Car => Owner_Car, others => 0.0);
            case K is
               when Grenade =>               --  an arc (~0.95 s), then it rolls a little
                  Q.Z := 1.0; Q.VZ := 5.5;
                  Q.VX := Cos (Ang) * Dist / 1.2; Q.VY := Sin (Ang) * Dist / 1.2;
                  if Drop_Z > 2.0 then          --  bombing from the air: falls, then the fuse
                     Q.Z := Drop_Z; Q.VZ := 0.0;
                     Q.VX := Cars (Owner_Car).VX; Q.VY := Cars (Owner_Car).VY;
                     Q.T := -Sqrt (2.0 * Drop_Z / 14.0);
                  end if;
                  Sound.Play (Sound.Launch, 0.4 * Att (X, Y));
               when Rocket =>
                  Q.Z := 1.0; Q.VX := Cos (Ang) * 42.0; Q.VY := Sin (Ang) * 42.0;
                  Sound.Play (Sound.Launch, Att (X, Y));
               when Shell =>
                  Q.Z := 1.5; Q.VX := Cos (Ang) * 60.0; Q.VY := Sin (Ang) * 60.0;
                  Sound.Play (Sound.Cannon, Att (X, Y, 300.0));
                  Particle (X, Y, Flash);
                  for N in 1 .. 4 loop
                     Particle (X, Y, Smoke);
                  end loop;
            end case;
            return;
         end if;
      end loop;
   end Launch;

   procedure Update_Projectiles (DT : Float) is
   begin
      for Q of Projs loop
         if Q.Active then
            Q.T := Q.T + DT;
            case Q.Kind is
               when Grenade =>
                  Q.VZ := Q.VZ - 14.0 * DT;
                  Q.Z := Q.Z + Q.VZ * DT;
                  if Q.Z <= 0.0 then               --  bounce and roll
                     Q.Z := 0.0;
                     Q.VZ := (if abs Q.VZ > 1.5 then -Q.VZ * 0.35 else 0.0);
                     Q.VX := Q.VX * (1.0 - Float'Min (1.0, DT * 4.0));
                     Q.VY := Q.VY * (1.0 - Float'Min (1.0, DT * 4.0));
                     if World.Cell (Q.X, Q.Y) = 2 then
                        Particle (Q.X, Q.Y, Splash);
                        Sound.Play (Sound.Splash, 0.5 * Att (Q.X, Q.Y));
                        Q.Active := False;
                     end if;
                  end if;
                  if Q.Active and then Q.Z < 1.4 then     --  bounces off cars it hits low
                     for C of Cars loop
                        if C.Active and then abs (C.X - Q.X) < 6.0 and then abs (C.Y - Q.Y) < 6.0 then
                           declare
                              EX : constant Float := Q.X + Q.VX * DT - C.X;
                              EY : constant Float := Q.Y + Q.VY * DT - C.Y;
                           begin
                              if abs (EX * Cos (C.A) + EY * Sin (C.A)) < Params (C.Kind).Len / 2.0
                                and then abs (-EX * Sin (C.A) + EY * Cos (C.A)) < Params (C.Kind).Wid / 2.0
                              then
                                 Q.VX := -Q.VX * 0.3; Q.VY := -Q.VY * 0.3;
                                 exit;
                              end if;
                           end;
                        end if;
                     end loop;
                  end if;
                  if Q.Active then
                     if World.Solid (Q.X + Q.VX * DT, Q.Y) then
                        Q.VX := -Q.VX * 0.5;
                     else
                        Q.X := Q.X + Q.VX * DT;
                     end if;
                     if World.Solid (Q.X, Q.Y + Q.VY * DT) then
                        Q.VY := -Q.VY * 0.5;
                     else
                        Q.Y := Q.Y + Q.VY * DT;
                     end if;
                     if Q.T > 1.9 then
                        Q.Active := False;
                        Blast (Q.X, Q.Y, Weapons (4).Rng, Weapons (4).Dmg, Q.By);
                     end if;
                  end if;
               when Rocket | Shell =>
                  declare
                     Sp    : constant Float := Hypot (Q.VX, Q.VY);
                     Steps : constant Positive := Positive'Max (1, Integer (Sp * DT / 0.5));
                     Hit   : Boolean := False;
                     Hit_C : Car_Ref := 0;
                  begin
                     if Q.Kind = Rocket then
                        Particle (Q.X, Q.Y, Smoke);
                     end if;
                     for St in 1 .. Steps loop
                        Q.X := Q.X + Q.VX * DT / Float (Steps);
                        Q.Y := Q.Y + Q.VY * DT / Float (Steps);
                        Q.Dist := Q.Dist + Sp * DT / Float (Steps);
                        if World.Solid (Q.X, Q.Y) or else Q.Dist > 140.0 then
                           Hit := True;
                        end if;
                        for I in Cars'Range loop
                           exit when Hit;
                           declare
                              C : Car renames Cars (I);
                           begin
                              if C.Active and then I /= Q.Owner_Car and then not C.Sunk and then C.Z < 3.0
                                and then abs (C.X - Q.X) < 7.0 and then abs (C.Y - Q.Y) < 7.0
                              then
                                 declare
                                    EX : constant Float := Q.X - C.X;
                                    EY : constant Float := Q.Y - C.Y;
                                 begin
                                    if abs (EX * Cos (C.A) + EY * Sin (C.A)) < Params (C.Kind).Len / 2.0
                                      and then abs (-EX * Sin (C.A) + EY * Cos (C.A)) < Params (C.Kind).Wid / 2.0
                                    then
                                       Hit := True; Hit_C := I;
                                    end if;
                                 end;
                              end if;
                           end;
                        end loop;
                        for I in Peds'Range loop
                           exit when Hit;
                           if Peds (I).Active and then not Peds (I).Dead and then I /= Q.Owner_Ped
                             and then not (Peds (I).Is_Player and then Player_Car /= 0)
                             and then abs (Peds (I).X - Q.X) < 0.7 and then abs (Peds (I).Y - Q.Y) < 0.7
                           then
                              Hit := True;
                           end if;
                        end loop;
                        exit when Hit;
                     end loop;
                     if Hit then
                        Q.Active := False;
                        if Hit_C /= 0 then         --  a direct hit wrecks a car outright
                           Damage (Cars (Hit_C), (if Q.Kind = Shell then 700.0 else 400.0), Q.By);
                           if Cars (Hit_C).HP <= 0.0 then
                              Cars (Hit_C).Fire_T := Float'Min (Cars (Hit_C).Fire_T, 0.15);
                           end if;
                        end if;
                        Blast (Q.X - Q.VX * 0.01, Q.Y - Q.VY * 0.01,
                               (if Q.Kind = Shell then 7.0 else Weapons (5).Rng),
                               (if Q.Kind = Shell then 300.0 else Weapons (5).Dmg), Q.By);
                     end if;
                  end;
            end case;
         end if;
      end loop;
   end Update_Projectiles;

   procedure Fire_Weapon (Shooter : Ped_Ref; X, Y, Angle : Float; W : Natural; From_Car : Car_Ref) is
      WI     : Weapon_Info renames Weapons (W);
      Is_P   : constant Boolean := Shooter = Player;
      S      : Ped renames Peds (Shooter);
      Ang    : Float := Angle;
      Who    : constant Culprit := (if Is_P then By_Player elsif S.Cop then By_Cop else By_NPC);
   begin
      S.Shoot_T := WI.Rate;
      if WI.Melee then
         Sound.Play (Sound.Punch, Att (S.X, S.Y));
         for I in Peds'Range loop
            declare
               P : Ped renames Peds (I);
            begin
               if I /= Shooter and then P.Active and then not P.Dead
                 and then not (P.Is_Player and then Player_Car /= 0)
               then
                  declare
                     DX : constant Float := P.X - S.X;
                     DY : constant Float := P.Y - S.Y;
                     D  : constant Float := Hypot (DX, DY);
                  begin
                     if D < WI.Rng and then D > 0.01 and then abs Ang_Diff (Ang, Arctan (DY, DX)) < 0.9 then
                        Hurt_Ped (I, WI.Dmg, Who, DX / D, DY / D);
                        if Is_P then
                           Add_Heat ((if Cops_Near (P.X, P.Y, 30.0) then 0.5 else 0.1));
                        end if;
                        exit;
                     end if;
                  end;
               end if;
            end;
         end loop;
         return;
      end if;
      if Is_P then
         Ammo (W) := Ammo (W) - 1;
      end if;
      case W is
         when 4 | 5 =>
            declare
               Dist : Float := 12.0;
            begin
               if Is_P and then Mouse_Down and then Player_Car = 0 then
                  declare
                     WX, WY : Float;
                  begin
                     Screen_To_World (Mouse_X, Mouse_Y, WX, WY);
                     Dist := Clamp (Hypot (WX - X, WY - Y), 4.0, 20.0);
                  end;
               end if;
               if W = 4 and then From_Car /= 0 and then Cars (From_Car).Z > 2.0 then
                  Launch (Grenade, X, Y, Ang, Who, Shooter, From_Car, 0.0);
               elsif W = 4 and then From_Car /= 0 then      --  from a car: drop it out of the back
                  Launch (Grenade, X - Cos (Ang) * (Params (Cars (From_Car).Kind).Len + 1.0),
                          Y - Sin (Ang) * (Params (Cars (From_Car).Kind).Len + 1.0), Ang + Pi, Who, Shooter,
                          From_Car, 1.0);
               else
                  Launch ((if W = 4 then Grenade else Rocket), X, Y, Ang, Who, Shooter, From_Car, Dist);
               end if;
            end;
         when 3 =>
            Sound.Play (Sound.Shot_Shotgun, Att (X, Y));
            for Pellet in 1 .. 6 loop
               Fire_Ray (Shooter, X, Y, Ang, W, From_Car);
            end loop;
         when others =>
            Sound.Play ((if W = 2 then Sound.Shot_SMG else Sound.Shot_Pistol), Att (X, Y));
            Fire_Ray (Shooter, X, Y, Ang, W, From_Car);
      end case;
      Scare_Around (X, Y, 35.0, 7.0);
      if Is_P then
         Add_Heat ((if Cops_Near (X, Y, 50.0) then 0.2 else 0.02));
      end if;
   end Fire_Weapon;

   ------------------------------------------------------------------ cars in/out
   procedure Enter_Car is
      P    : Ped renames Peds (Player);
      Best : Car_Ref := 0;
      BD   : Float := 3.2;
   begin
      for I in Cars'Range loop
         declare
            C : Car renames Cars (I);
         begin
            if C.Active and then not C.Dead and then not C.Sunk and then C.Fire_T <= 0.0 then
               declare
                  DX : constant Float := P.X - C.X;
                  DY : constant Float := P.Y - C.Y;
                  FX : constant Float := Cos (C.A);
                  FY : constant Float := Sin (C.A);
                  LX : constant Float := abs (DX * FX + DY * FY) - Params (C.Kind).Len / 2.0;
                  LY : constant Float := abs (-DX * FY + DY * FX) - Params (C.Kind).Wid / 2.0;
                  D  : constant Float := Hypot (Float'Max (0.0, LX), Float'Max (0.0, LY));
               begin
                  if D < BD then
                     BD := D;
                     Best := I;
                  end if;
               end;
            end if;
         end;
      end loop;
      if Best = 0 then
         return;
      end if;
      declare
         C : Car renames Cars (Best);
      begin
         if C.Driver = AI_Driver then
            --  carjack: throw the driver out
            declare
               Off : constant Float := Params (C.Kind).Wid / 2.0 + 0.6;
               Is_Cop : constant Boolean := C.Kind = Police;
               D : constant Ped_Ref := Alloc_Ped (C.X + Sin (C.A) * Off, C.Y - Cos (C.A) * Off,
                                                  Cop => Is_Cop and then Heat >= 1.0);
            begin
               if D /= 0 and then not Peds (D).Cop then
                  Ped_Scare (Peds (D), P.X, P.Y, 8.0);
               end if;
               if Is_Cop then
                  Add_Heat (1.4, True);
               elsif Cops_Near (P.X, P.Y, 45.0) then
                  Add_Heat (0.6, True);
               elsif Heat >= 1.0 then
                  Add_Heat (0.3);
               end if;
               Scare_Around (C.X, C.Y, 15.0, 5.0);
            end;
         elsif C.Kind = Police then
            Add_Heat (1.0, True);
         end if;
         C.Driver := Player_Driver;
         C.Siren := False;
         C.Throttle := 0.0; C.Steer := 0.0; C.Handbrake := False;
         C.AI.Mode := Traffic;
         Player_Car := Best;
         Bail_Warn := False;
         Say (To_String (Car_Names (C.Kind)), 1.5);
         if C.Kind = Tank and then Heat < 4.0 then
            Heat := 4.0;
            Seen_T := 0.0;
            Star_Flash := 1.5;
            Show_Big ("CHAR D'ASSAUT", Yellow, 3.0, "You stole a tank. Aim with the mouse / right stick - the army is coming");
         end if;
      end;
   end Enter_Car;

   procedure Place_Beside (CI : Car_Ref; Ok : out Boolean) is
      C  : Car renames Cars (CI);
      P  : Ped renames Peds (Player);
      RX : constant Float := -Sin (C.A);
      RY : constant Float := Cos (C.A);
      W2 : constant Float := Params (C.Kind).Wid / 2.0 + 0.6;
      L2 : constant Float := Params (C.Kind).Len / 2.0 + 0.7;
      type Off is record
         X, Y : Float;
      end record;
      Tries : constant array (1 .. 4) of Off :=
        ((-RX * W2, -RY * W2), (RX * W2, RY * W2), (Cos (C.A) * L2, Sin (C.A) * L2),
         (-Cos (C.A) * L2, -Sin (C.A) * L2));
   begin
      Ok := False;
      for T of Tries loop
         if not World.Blocked (C.X + T.X, C.Y + T.Y) then
            P.X := C.X + T.X;
            P.Y := C.Y + T.Y;
            Ok := True;
            return;
         end if;
      end loop;
      if Is_Boat (C.Kind) then          --  step ashore onto a quay within a few metres
         for R in 1 .. 12 loop
            for K in 0 .. 15 loop
               declare
                  A : constant Float := Float (K) * Pi / 8.0;
                  X : constant Float := C.X + Cos (A) * (W2 + Float (R) * 0.5);
                  Y : constant Float := C.Y + Sin (A) * (W2 + Float (R) * 0.5);
               begin
                  if not World.Blocked (X, Y) then
                     P.X := X; P.Y := Y;
                     Ok := True;
                     return;
                  end if;
               end;
            end loop;
         end loop;
      end if;
   end Place_Beside;

   procedure Exit_Car (Force : Boolean := False) is
      Ok : Boolean;
   begin
      if Player_Car = 0 then
         return;
      end if;
      declare
         C : Car renames Cars (Player_Car);
      begin
         if not Force and then C.Z > 0.5 then
            Say ("Land first: hold Space (or A) over open ground", 2.0);
            return;
         end if;
         if not Force and then Speed (C) > 9.0 and then C.Fire_T <= 0.0 then
            Say ("Slow down to get out", 1.0);
            return;
         end if;
         C.Z := 0.0;
         Place_Beside (Player_Car, Ok);
         if not Ok then
            if not Force then
               Say ((if Is_Boat (C.Kind) then "Steer next to a quay to get out" else "No room to get out"), 1.5);
               return;
            end if;
            Peds (Player).X := C.X;
            Peds (Player).Y := C.Y;
         end if;
         C.Driver := No_Driver;
         C.Throttle := 0.0; C.Steer := 0.0; C.Handbrake := True;
         Player_Car := 0;
      end;
   end Exit_Car;

   procedure Cycle_Weapon (Dir : Integer := 1) is
      N : constant := Max_Weapon + 1;
   begin
      for I in 1 .. N loop
         declare
            W : constant Natural := (Weapon + N + I * Dir) mod N;
         begin
            if W = 0 or else Ammo (W) > 0 then
               Weapon := W;
               exit;
            end if;
         end;
      end loop;
   end Cycle_Weapon;

   ------------------------------------------------------------------ player control
   procedure Control_Player (DT : Float) is
      P : Ped renames Peds (Player);
   begin
      P.Moving := False;
      if Secrets.Busy then
         return;                --  crawling through the catacombs
      end if;
      if Hit (K_Q) or else Hit (K_Tab) or else Gamepad.Hit (Gamepad.D_Right)
        or else (Player_Car = 0 and then Gamepad.Hit (Gamepad.RB))
      then
         Cycle_Weapon;
      end if;
      if Gamepad.Hit (Gamepad.LB) or else Gamepad.Hit (Gamepad.D_Left) then
         Cycle_Weapon (-1);
      end if;
      if Hit (K_1) then
         Weapon := 0;
      end if;
      if Hit (K_2) and then Ammo (1) > 0 then
         Weapon := 1;
      end if;
      if Hit (K_3) and then Ammo (2) > 0 then
         Weapon := 2;
      end if;
      if Hit (K_4) and then Ammo (3) > 0 then
         Weapon := 3;
      end if;
      if Hit (K_5) and then Ammo (4) > 0 then
         Weapon := 4;
      end if;
      if Hit (K_6) and then Ammo (5) > 0 then
         Weapon := 5;
      end if;
      P.Shoot_T := P.Shoot_T - DT;
      if Player_Car /= 0 then
         declare
            C : Car renames Cars (Player_Car);
         begin
            C.Throttle := Clamp ((if Down (K_Up) then 1.0 else 0.0) - (if Down (K_Down) then 1.0 else 0.0)
                                 + Gamepad.RT - Gamepad.LT, -1.0, 1.0);
            C.Steer := Clamp ((if Down (K_Right) then 1.0 else 0.0) - (if Down (K_Left) then 1.0 else 0.0)
                              + Gamepad.LX, -1.0, 1.0);
            C.Handbrake := Down (K_Space) or else Gamepad.Down (Gamepad.A) or else Gamepad.Down (Gamepad.RB);
            if Hit (K_H) or else Gamepad.Hit (Gamepad.B) then
               Sound.Play (Sound.Horn);
               Scare_Around (C.X, C.Y, 12.0, 3.0);
            end if;
            P.X := C.X; P.Y := C.Y; P.A := C.A;
            if C.Kind = Tank then
               --  the turret follows the mouse or the right stick; it fires shells
               declare
                  Aim : Float := C.Turret;
                  WX, WY : Float;
               begin
                  if Hypot (Gamepad.RX, Gamepad.RY) > 0.35 then
                     Aim := Arctan (Gamepad.RY, Gamepad.RX);
                  elsif Mouse_X > 0.0 or else Mouse_Y > 0.0 then
                     Screen_To_World (Mouse_X, Mouse_Y, WX, WY);
                     Aim := Arctan (WY - C.Y, WX - C.X);
                  end if;
                  C.Turret := C.Turret + Clamp (Ang_Diff (C.Turret, Aim), -2.2 * DT, 2.2 * DT);
                  C.Gun_T := C.Gun_T - DT;
                  if (Down (K_Ctrl) or else Down (K_X) or else Mouse_Down or else Gamepad.Down (Gamepad.X))
                    and then C.Gun_T <= 0.0
                  then
                     C.Gun_T := 1.3;
                     Launch (Shell, C.X + Cos (C.Turret) * 4.2, C.Y + Sin (C.Turret) * 4.2, C.Turret,
                             By_Player, Player, Player_Car);
                     C.VX := C.VX - Cos (C.Turret) * 1.5;
                     C.VY := C.VY - Sin (C.Turret) * 1.5;
                     Shake := Float'Max (Shake, 0.5);
                  end if;
               end;
            elsif (Down (K_Ctrl) or else Down (K_X) or else Mouse_Down or else Gamepad.Down (Gamepad.X))
              and then Weapon > 0 and then P.Shoot_T <= 0.0 and then Ammo (Weapon) > 0
            then
               declare
                  F : constant Float := Params (C.Kind).Len / 2.0 + 0.3;
               begin
                  Fire_Weapon (Player, C.X + Cos (C.A) * F, C.Y + Sin (C.A) * F, C.A, Weapon, Player_Car);
               end;
            end if;
            if C.Fire_T > 0.0 and then C.Fire_T < 2.5 and then not Bail_Warn then
               Say ("Your car is on fire - get out! (F)", 2.0);
               Bail_Warn := True;
            end if;
            if Hit (K_F) or else Hit (K_Enter) or else Gamepad.Hit (Gamepad.Y) then
               Exit_Car;
            end if;
         end;
         return;
      end if;
      declare
         MX : Float := (if Down (K_Right) then 1.0 else 0.0) - (if Down (K_Left) then 1.0 else 0.0);
         MY : Float := (if Down (K_Down) then 1.0 else 0.0) - (if Down (K_Up) then 1.0 else 0.0);
         Shoot : constant Boolean := Down (K_Space) or else Down (K_Ctrl) or else Down (K_X)
           or else Gamepad.RT > 0.5;
         Sprint : constant Boolean := Down (K_Shift) or else Gamepad.Down (Gamepad.A)
           or else Gamepad.Down (Gamepad.LS);
      begin
         MX := MX + Gamepad.LX;
         MY := MY + Gamepad.LY;
         if MX /= 0.0 or else MY /= 0.0 then
            declare
               L : constant Float := Hypot (MX, MY);
               Amount : constant Float := Float'Min (1.0, L);   --  analog stick = analog speed
               S : constant Float := (if Sprint then 6.2 else 3.9) * DT * Amount;
            begin
               MX := MX / L; MY := MY / L;
               Ped_Move_By (P, MX * S, MY * S);
               P.A := Arctan (MY, MX);
               P.Moving := True;
            end;
         end if;
         --  twin-stick aiming with the right stick
         if Hypot (Gamepad.RX, Gamepad.RY) > 0.35 then
            P.A := Arctan (Gamepad.RY, Gamepad.RX);
         end if;
         if Mouse_Down then
            declare
               WX, WY : Float;
            begin
               Screen_To_World (Mouse_X, Mouse_Y, WX, WY);
               P.A := Arctan (WY - P.Y, WX - P.X);
            end;
         end if;
         if (Shoot or else Mouse_Down) and then P.Shoot_T <= 0.0 then
            if Weapon > 0 and then Ammo (Weapon) <= 0 then
               Cycle_Weapon;
            end if;
            Fire_Weapon (Player, P.X + Cos (P.A) * 0.6, P.Y + Sin (P.A) * 0.6, P.A, Weapon, 0);
         end if;
         if Hit (K_F) or else Hit (K_Enter) or else Gamepad.Hit (Gamepad.Y) then
            if not Secrets.Try_Manhole then
               Enter_Car;
            end if;
         end if;
      end;
   end Control_Player;

   ------------------------------------------------------------------ collisions
   procedure Collide_Cars is
      CA, CB : Circle_Array;
      NA, NB : Natural;
   begin
      for I in Cars'Range loop
         if Cars (I).Active and then not Cars (I).Sunk then
            for J in I + 1 .. Cars'Last loop
               if Cars (J).Active and then not Cars (J).Sunk
                 and then Is_Boat (Cars (I).Kind) = Is_Boat (Cars (J).Kind)    --  a boat passes under a bridge
                 and then Cars (I).Z < 2.0 and then Cars (J).Z < 2.0           --  aircraft fly over everything
               then
                  declare
                     A   : Car renames Cars (I);
                     B   : Car renames Cars (J);
                     Lim : constant Float := (Params (A.Kind).Len + Params (B.Kind).Len) / 2.0;
                  begin
                     if abs (A.X - B.X) <= Lim and then abs (A.Y - B.Y) <= Lim then
                        Circles (A, CA, NA);
                        Circles (B, CB, NB);
                        declare
                           Best_O : Float := 0.0;
                           HNX, HNY, HPX, HPY : Float := 0.0;
                        begin
                           for P of CA (1 .. NA) loop
                              for Q of CB (1 .. NB) loop
                                 declare
                                    DX : constant Float := Q.X - P.X;
                                    DY : constant Float := Q.Y - P.Y;
                                    D  : constant Float := Hypot (DX, DY);
                                    O  : constant Float := P.R + Q.R - D;
                                 begin
                                    if O > Best_O then
                                       Best_O := O;
                                       HNX := (if D > 0.0 then DX / D else 1.0);
                                       HNY := (if D > 0.0 then DY / D else 0.0);
                                       HPX := (P.X + Q.X) / 2.0;
                                       HPY := (P.Y + Q.Y) / 2.0;
                                    end if;
                                 end;
                              end loop;
                           end loop;
                           if Best_O > 0.0 then
                              declare
                                 MA  : constant Float := Params (A.Kind).Mass * (if A.Dead then 1.5 else 1.0);
                                 MB  : constant Float := Params (B.Kind).Mass * (if B.Dead then 1.5 else 1.0);
                                 Tot : constant Float := MA + MB;
                                 RV  : Float;
                              begin
                                 A.X := A.X - HNX * Best_O * MB / Tot; A.Y := A.Y - HNY * Best_O * MB / Tot;
                                 B.X := B.X + HNX * Best_O * MA / Tot; B.Y := B.Y + HNY * Best_O * MA / Tot;
                                 RV := (B.VX - A.VX) * HNX + (B.VY - A.VY) * HNY;
                                 if RV < 0.0 then
                                    declare
                                       Imp : constant Float := -1.3 * RV / (1.0 / MA + 1.0 / MB);
                                    begin
                                       A.VX := A.VX - Imp * HNX / MA; A.VY := A.VY - Imp * HNY / MA;
                                       B.VX := B.VX + Imp * HNX / MB; B.VY := B.VY + Imp * HNY / MB;
                                       A.AV := A.AV + ((HPX - A.X) * HNY - (HPY - A.Y) * HNX) * RV * 0.03 / MA;
                                       B.AV := B.AV - ((HPX - B.X) * HNY - (HPY - B.Y) * HNX) * RV * 0.03 / MB;
                                    end;
                                    if -RV > 5.0 then
                                       Damage (A, (-RV - 5.0) * 3.5 * MB / Tot * 2.0,
                                               (if B.Driver = Player_Driver then By_Player else Nobody));
                                       Damage (B, (-RV - 5.0) * 3.5 * MA / Tot * 2.0,
                                               (if A.Driver = Player_Driver then By_Player else Nobody));
                                       On_Crash (I, -RV, HPX, HPY);
                                       On_Crash (J, -RV, HPX, HPY);
                                       declare
                                          Other : constant Car_Ref :=
                                            (if I = Player_Car then J elsif J = Player_Car then I else 0);
                                       begin
                                          if Other /= 0 then
                                             if Cars (Other).Kind = Police and then -RV > 7.0 and then Heat < 1.0 then
                                                Add_Heat (1.0, True);
                                             end if;
                                             if Cars (Other).Driver = AI_Driver then
                                                Cars (Other).AI.Panic := 6.0;
                                             end if;
                                          end if;
                                       end;
                                    end if;
                                 end if;
                              end;
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end loop;
         end if;
      end loop;
   end Collide_Cars;

   procedure Collide_Cars_Peds is
      CC : Circle_Array;
      N  : Natural;
   begin
      for CI in Cars'Range loop
         declare
            C : Car renames Cars (CI);
         begin
            if C.Active and then not C.Sunk and then not Is_Boat (C.Kind) and then C.Z < 1.5 then
               declare
                  SP : constant Float := Speed (C);
                  L  : constant Float := Params (C.Kind).Len;
                  By : constant Culprit :=
                    (if C.Driver = Player_Driver or else (C.Driver = No_Driver and then C.Last_Hit = By_Player)
                     then By_Player else By_NPC);
               begin
                  Circles (C, CC, N);
                  for PI in Peds'Range loop
                     declare
                        P : Ped renames Peds (PI);
                     begin
                        if P.Active and then not P.Dead and then not (P.Is_Player and then Player_Car /= 0)
                          and then abs (P.X - C.X) <= L and then abs (P.Y - C.Y) <= L
                        then
                           for Q of CC (1 .. N) loop
                              declare
                                 DX : constant Float := P.X - Q.X;
                                 DY : constant Float := P.Y - Q.Y;
                                 D  : constant Float := Hypot (DX, DY);
                                 NX2 : constant Float := (if D > 0.0 then DX / D else 1.0);
                                 NY2 : constant Float := (if D > 0.0 then DY / D else 0.0);
                              begin
                                 if D < Q.R + 0.3 then
                                    if SP > 4.5 then
                                       if P.Is_Player then
                                          Hurt_Ped (PI, (SP - 4.0) * 7.0, By);
                                          P.X := P.X + NX2 * 1.5; P.Y := P.Y + NY2 * 1.5;
                                       else
                                          P.X := P.X + C.VX * 0.08; P.Y := P.Y + C.VY * 0.08;
                                          Kill_Ped (PI, By);
                                          for K in 1 .. 6 loop
                                             Particle (P.X, P.Y, Blood_Drop);
                                          end loop;
                                       end if;
                                    else
                                       P.X := Q.X + NX2 * (Q.R + 0.32);
                                       P.Y := Q.Y + NY2 * (Q.R + 0.32);
                                       if SP > 1.5 and then not P.Is_Player then
                                          Ped_Scare (P, C.X, C.Y, 3.0);
                                       end if;
                                    end if;
                                    exit;
                                 end if;
                              end;
                           end loop;
                        end if;
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;
   end Collide_Cars_Peds;

   ------------------------------------------------------------------ driving AI
   function Obstacle_Ahead (CI : Car_Ref; Range_M : Float) return Float is
      C    : Car renames Cars (CI);
      FX   : constant Float := Cos (C.A);
      FY   : constant Float := Sin (C.A);
      Best : Float := Range_M;
      Len2 : constant Float := Params (C.Kind).Len / 2.0;
      Wid2 : constant Float := Params (C.Kind).Wid / 2.0;
   begin
      C.AI.Blocked_By := 0;
      for J in Cars'Range loop
         declare
            O : Car renames Cars (J);
         begin
            if J /= CI and then O.Active and then not O.Sunk and then Is_Boat (O.Kind) = Is_Boat (C.Kind)
              and then O.Z < 2.0
            then
               declare
                  DX : constant Float := O.X - C.X;
                  DY : constant Float := O.Y - C.Y;
               begin
                  if abs DX < Range_M + 6.0 and then abs DY < Range_M + 6.0 then
                     declare
                        LX     : constant Float := DX * FX + DY * FY;
                        LY     : constant Float := -DX * FY + DY * FX;
                        Ignore : Boolean := False;
                     begin
                        if O.Driver = AI_Driver then
                           if O.AI.Blocked_By = CI and then C.Serial < O.Serial then
                              Ignore := True;
                           elsif C.AI.Wait_T > 3.0 then
                              Ignore := abs LY > 0.9 or else abs Ang_Diff (C.A, O.A) > 0.8;
                           end if;
                        elsif O.Driver = No_Driver and then C.AI.Wait_T > 3.0 then
                           Ignore := abs LY > 0.9;      --  squeeze past a badly parked car
                        end if;
                        if not Ignore then
                           declare
                              Half : constant Float := Params (O.Kind).Wid / 2.0
                                - (if O.Driver = No_Driver then 0.35 else 0.0) + Wid2 + 0.1;
                           begin
                              if LX > 0.0 and then abs LY < Half then
                                 declare
                                    Gap : constant Float := LX - Len2 - Params (O.Kind).Len / 2.0;
                                 begin
                                    if Gap < Best then
                                       Best := Gap;
                                       C.AI.Blocked_By := J;
                                    end if;
                                 end;
                              end if;
                           end;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;
      end loop;
      for P of Peds loop
         if P.Active and then not P.Dead and then not (P.Is_Player and then Player_Car /= 0)
           and then abs (P.X - C.X) < 25.0 and then abs (P.Y - C.Y) < 25.0
         then
            declare
               DX : constant Float := P.X - C.X;
               DY : constant Float := P.Y - C.Y;
               LX : constant Float := DX * FX + DY * FY;
               LY : constant Float := -DX * FY + DY * FX;
            begin
               if LX > 0.0 and then abs LY < 0.3 + Wid2 + 0.1 then
                  Best := Float'Min (Best, LX - Len2 - 0.3);
               end if;
            end;
         end if;
      end loop;
      return Best;
   end Obstacle_Ahead;

   procedure Drive_Traffic (CI : Car_Ref; DT : Float) is
      C  : Car renames Cars (CI);
      AI : AI_State renames C.AI;
      SP : constant Float := Float'Max (0.0, Fwd_Speed (C));
      TX, TY, Desired, B, Gap : Float;
   begin
      Extend_Random (C);
      AI_Target (C, 5.0 + SP * 0.5, TX, TY);
      B := Bend (C);
      Desired := (if Secrets.Strike then 0.0 else AI.Cruise * (if AI.Panic > 0.0 then 1.6 else 1.0));
      if B > 0.6 then
         Desired := Float'Min (Desired, 4.0 + 10.0 * (1.0 - Float'Min (1.0, (B - 0.6) / 1.2)));
      end if;
      Gap := Obstacle_Ahead (CI, 6.0 + SP * 1.6);
      if Gap < 4.0 + SP * 1.4 then
         Desired := Float'Min (Desired, Float'Max (0.0, (Gap - 2.0) * 0.9));
      end if;
      if AI.Panic > 0.0 then
         AI.Panic := AI.Panic - DT;
      end if;
      Steer_To (C, TX, TY, Desired, DT);
      if Gap < 3.0 and then SP < 1.0 then
         AI.Wait_T := AI.Wait_T + DT;
         if AI.Wait_T > 2.0 and then AI.Wait_T - DT <= 2.0 then
            Sound.Play (Sound.Horn, 0.6 * Att (C.X, C.Y, 60.0));     --  impatient Parisian
         end if;
         if AI.Wait_T > 2.0 then
            declare
               D : constant Float := Params (C.Kind).Len / 2.0 + 2.0;
            begin
               Scare_Around (C.X + Cos (C.A) * D, C.Y + Sin (C.A) * D, 2.5, 3.0);
            end;
         end if;
         if AI.Wait_T > 9.0 then
            AI.Rev_T := 1.2;
            AI.Wait_T := 0.0;
         end if;
      elsif SP > 3.0 then
         AI.Wait_T := 0.0;
      end if;
   end Drive_Traffic;

   procedure Deploy_Cops (CI : Car_Ref; N : Positive) is
      C  : Car renames Cars (CI);
      RX : constant Float := -Sin (C.A);
      RY : constant Float := Cos (C.A);
      W2 : constant Float := Params (C.Kind).Wid / 2.0 + 0.6;
   begin
      for I in 1 .. N loop
         declare
            S   : constant Float := (if I mod 2 = 0 then 1.0 else -1.0);
            X   : Float := C.X + RX * S * W2;
            Y   : Float := C.Y + RY * S * W2;
            Cop : Ped_Ref;
         begin
            if World.Blocked (X, Y) then
               X := C.X; Y := C.Y;
            end if;
            Cop := Alloc_Ped (X, Y, Cop => True);
            if Cop /= 0 then
               Peds (Cop).Home_Car := CI;
               Peds (Cop).Shoot_T := Rand (0.8, 1.6);
            end if;
         end;
      end loop;
   end Deploy_Cops;

   procedure Park_And_Deploy (CI : Car_Ref) is
      C : Car renames Cars (CI);
   begin
      C.Deployed := True;
      C.Driver := No_Driver;
      C.Throttle := 0.0; C.Steer := 0.0; C.Handbrake := True;
      Deploy_Cops (CI, 2);
   end Park_And_Deploy;

   procedure Drive_Police (CI : Car_Ref; DT : Float) is
      C   : Car renames Cars (CI);
      AI  : AI_State renames C.AI;
      TXp : constant Float := (if Player_Car /= 0 then Cars (Player_Car).X else PX);
      TYp : constant Float := (if Player_Car /= 0 then Cars (Player_Car).Y else PY);
      TVX : constant Float := (if Player_Car /= 0 then Cars (Player_Car).VX else 0.0);
      TVY : constant Float := (if Player_Car /= 0 then Cars (Player_Car).VY else 0.0);
      D   : constant Float := Hypot (TXp - C.X, TYp - C.Y);
      SP  : constant Float := Float'Max (0.0, Fwd_Speed (C));
      TX, TY  : Float;
      Desired : Float := Params (C.Kind).Max * 0.78;
   begin
      AI.Repath := AI.Repath - DT;
      if C.Kind = Tank then
         declare
            Aim : constant Float := Arctan (TYp - C.Y, TXp - C.X);
         begin
            C.Turret := C.Turret + Clamp (Ang_Diff (C.Turret, Aim), -1.5 * DT, 1.5 * DT);
            C.Gun_T := C.Gun_T - DT;
            if C.Gun_T <= 0.0 and then D < 55.0 and then abs Ang_Diff (C.Turret, Aim) < 0.15
              and then World.LOS (C.X, C.Y, TXp, TYp)
            then
               C.Gun_T := 4.0;
               Launch (Shell, C.X + Cos (C.Turret) * 4.2, C.Y + Sin (C.Turret) * 4.2,
                       C.Turret + Rand (-0.06, 0.06), By_Cop, 0, CI);
            end if;
         end;
      end if;
      if D < 45.0 and then World.LOS (C.X, C.Y, TXp, TYp) then
         TX := TXp + TVX * 0.5;
         TY := TYp + TVY * 0.5;
         if Player_Car /= 0 then
            Desired := Float'Max (12.0, Speed (Cars (Player_Car)) + 8.0);
         else
            Desired := (if D > 18.0 then 14.0 else 0.0);
         end if;
         AI.Len := 0;
         if C.Kind = Tank then
            Desired := (if D > 25.0 then Desired else 0.0);      --  keep its distance and shoot
         elsif Player_Car = 0 and then D < 20.0 and then SP < 3.0 and then not C.Deployed then
            Park_And_Deploy (CI);
            return;
         end if;
         if Player_Car /= 0 and then D < 9.0 and then Speed (Cars (Player_Car)) < 2.0
           and then not C.Deployed and then Heat >= 1.0 and then C.Kind /= Tank
         then
            Park_And_Deploy (CI);
            return;
         end if;
      else
         if AI.Len = 0 or else AI.Repath <= 0.0 then
            AI.Repath := 1.5;
            declare
               A   : constant Integer := Nearest (Car_Graph, C.X, C.Y, 80.0);
               B   : constant Integer := Nearest (Car_Graph, TXp, TYp, 120.0);
               Tmp : Int_Array (1 .. Max_Path);
               Len : Natural;
            begin
               Find_Path (A, B, Tmp, Len);
               if Len > 0 then
                  for K in 1 .. Len loop
                     AI.Path (K) := Tmp (K);
                  end loop;
                  AI.Len := Len;
                  AI.Idx := 1;
               end if;
            end;
         end if;
         if AI.Len > 0 then
            AI_Target (C, 6.0 + SP * 0.5, TX, TY);
            declare
               B : constant Float := Bend (C);
            begin
               if B > 0.5 then
                  Desired := Float'Min (Desired, 6.0 + 14.0 * (1.0 - Float'Min (1.0, (B - 0.5) / 1.3)));
               end if;
            end;
            if AI.Idx >= AI.Len then
               AI.Repath := 0.0;
            end if;
         else
            TX := TXp; TY := TYp;
         end if;
      end if;
      Steer_To (C, TX, TY, Desired, DT);
   end Drive_Police;

   ------------------------------------------------------------------ boats
   function No_Car_Overlap (X, Y, Len : Float) return Boolean;

   --  open water ahead: how far a boat can go from (X, Y) in direction A (up to Max)
   function Feeler (X, Y, A, Max : Float) return Float is
      D : Float := 2.0;
   begin
      while D < Max loop
         exit when not World.Navigable (X + Cos (A) * D, Y + Sin (A) * D);
         D := D + 2.0;
      end loop;
      return D;
   end Feeler;

   --  steering by feelers: try a fan of headings, prefer open water (and the target when chasing)
   procedure Drive_Boat (CI : Car_Ref; DT : Float) is
      C      : Car renames Cars (CI);
      AI     : AI_State renames C.AI;
      Chase  : constant Boolean := AI.Mode = Pursuit;
      TX     : constant Float := (if Player_Car /= 0 then Cars (Player_Car).X else PX);
      TY     : constant Float := (if Player_Car /= 0 then Cars (Player_Car).Y else PY);
      To_T   : constant Float := Arctan (TY - C.Y, TX - C.X);
      Best_H : Float := C.A;
      Best_S : Float := -1.0E9;
      Cruise : constant Float := (if Chase then Params (C.Kind).Max * 0.85 else AI.Cruise);
      VF     : constant Float := Fwd_Speed (C);
      Ahead  : Float;
   begin
      if AI.Rev_T > 0.0 then                       --  backing out of a dead end
         AI.Rev_T := AI.Rev_T - DT;
         C.Throttle := -0.7;
         C.Steer := 0.6;
         return;
      end if;
      for K in -6 .. 6 loop
         declare
            H : constant Float := C.A + Float (K) * 0.33;
            F : constant Float := Feeler (C.X, C.Y, H, 70.0);
            S : Float := Float'Min (F, 60.0) / 60.0 - abs Float (K) * 0.03;
         begin
            if F < Params (C.Kind).Len then
               S := S - 1.0;
            end if;
            if Chase then
               S := S + 0.9 * Cos (Ang_Diff (H, To_T));
            end if;
            if S > Best_S then
               Best_S := S; Best_H := H;
            end if;
         end;
      end loop;
      Ahead := Feeler (C.X, C.Y, C.A, 40.0);
      C.Steer := Clamp (Ang_Diff (C.A, Best_H) * 1.8, -1.0, 1.0);
      declare
         Want : constant Float := Cruise * Float'Min (1.0, Ahead / (Params (C.Kind).Len * 1.5 + 8.0));
      begin
         C.Throttle := Clamp ((Want - VF) / 3.0, -1.0, 1.0);
      end;
      if abs VF < 0.5 and then Ahead < Params (C.Kind).Len then
         AI.Stuck_T := AI.Stuck_T + DT;
         if AI.Stuck_T > 2.0 then
            AI.Rev_T := 2.5;
            AI.Stuck_T := 0.0;
         end if;
      else
         AI.Stuck_T := 0.0;
      end if;
      --  police boats shoot at you from the water
      if Chase and then C.Kind = Police_Boat then
         C.Gun_T := C.Gun_T - DT;
         declare
            D : constant Float := Hypot (TX - C.X, TY - C.Y);
         begin
            if C.Gun_T <= 0.0 and then D < 28.0 and then World.LOS (C.X, C.Y, TX, TY) then
               C.Gun_T := 0.9;
               Sound.Play (Sound.Shot_Pistol, Att (C.X, C.Y));
               Add_Tracer (C.X, C.Y, TX + Rand (-1.0, 1.0), TY + Rand (-1.0, 1.0));
               if Rand < 0.45 then
                  if Player_Car /= 0 then
                     Damage (Cars (Player_Car), 10.0, By_Cop);
                  else
                     Hurt_Ped (Player, 9.0, By_Cop);
                  end if;
               end if;
            end if;
         end;
      end if;
   end Drive_Boat;

   --  a spot on open water R0 .. R1 from the player where a boat of kind K fits
   procedure Water_Spot (K : Car_Type; R0, R1 : Float; X, Y, A : out Float; Ok : out Boolean;
                         Visible_Ok : Boolean := False) is
      T : Car;
   begin
      Ok := False; X := 0.0; Y := 0.0; A := 0.0;
      T.Kind := K;
      for Try in 1 .. 40 loop
         declare
            An : constant Float := Rand (0.0, 2.0 * Pi);
            R  : constant Float := Rand (R0, R1);
         begin
            T.X := PX + Cos (An) * R;
            T.Y := PY + Sin (An) * R;
            if World.Navigable (T.X, T.Y) and then World.In_Bounds (T.X, T.Y)
              and then (Visible_Ok or else not On_Screen (T.X, T.Y, Params (K).Len))
            then
               --  heading along the channel: the direction with the most open water
               declare
                  Best : Float := 0.0;
               begin
                  for H in 0 .. 11 loop
                     declare
                        F : constant Float := Feeler (T.X, T.Y, Float (H) * Pi / 6.0, 80.0);
                     begin
                        if F > Best then
                           Best := F; T.A := Float (H) * Pi / 6.0;
                        end if;
                     end;
                  end loop;
               end;
               if Fits (T) and then No_Car_Overlap (T.X, T.Y, Params (K).Len) then
                  X := T.X; Y := T.Y; A := T.A;
                  Ok := True;
                  return;
               end if;
            end if;
         end;
      end loop;
   end Water_Spot;

   Boat_T : Float := 0.0;

   procedure Manage_Boats (DT : Float) is
      Tours, Cops : Natural := 0;
      On_Water    : constant Boolean := Player_Car /= 0 and then Is_Boat (Cars (Player_Car).Kind);
   begin
      Boat_T := Boat_T - DT;
      for I in Cars'Range loop
         declare
            C : Car renames Cars (I);
         begin
            if C.Active and then Is_Boat (C.Kind) and then C.Driver = AI_Driver then
               if C.AI.Mode = Pursuit then
                  Cops := Cops + 1;
                  if Stars = 0 or else not On_Water then        --  the river police give up
                     C.AI.Mode := Traffic;
                     C.Siren := False;
                  end if;
               elsif C.Kind = Tourboat then
                  Tours := Tours + 1;
               end if;
            end if;
            --  a moving boat leaves a wake
            if C.Active and then Is_Boat (C.Kind) and then not C.Sunk and then Speed (C) > 2.5
              and then Rand < DT * (6.0 + Speed (C) * 0.5) and then On_Screen (C.X, C.Y, 10.0)
            then
               declare
                  B : constant Float := Params (C.Kind).Len / 2.0;
                  S : constant Float := (if Rand < 0.5 then -1.0 else 1.0) * Params (C.Kind).Wid * 0.4;
               begin
                  Particle (C.X - Cos (C.A) * B - Sin (C.A) * S, C.Y - Sin (C.A) * B + Cos (C.A) * S, Splash);
               end;
            end if;
         end;
      end loop;
      if Boat_T > 0.0 or else Mode /= Play then
         return;
      end if;
      Boat_T := 2.0;
      declare
         X, Y, A : Float;
         Ok      : Boolean;
         CI      : Car_Ref;
      begin
         if Tours < 2 then
            Water_Spot (Tourboat, 120.0, 320.0, X, Y, A, Ok);
            if Ok then
               CI := Alloc_Car (Tourboat, X, Y, A);
               if CI /= 0 then
                  Cars (CI).Driver := AI_Driver;
                  Cars (CI).AI := (Mode => Traffic, Cruise => Rand (4.0, 6.0), others => <>);
               end if;
            end if;
         end if;
         if On_Water and then Stars >= 1 and then Cops < Natural'Min (Stars, 3) then
            Water_Spot (Police_Boat, 90.0, 220.0, X, Y, A, Ok);
            if Ok then
               CI := Alloc_Car (Police_Boat, X, Y, A);
               if CI /= 0 then
                  Cars (CI).Driver := AI_Driver;
                  Cars (CI).AI := (Mode => Pursuit, Cruise => 20.0, others => <>);
                  Cars (CI).Siren := True;
                  Cars (CI).Gun_T := 2.0;
               end if;
            end if;
         end if;
      end;
   end Manage_Boats;

   --  speedboats moored at quays near the river landmarks, there to be found
   procedure Moor_Boats is
      Paris_Moorings : constant String :=
        "Pont Neuf;Ile Saint-Louis;Notre-Dame;Tour Eiffel;Bercy;Canal Saint-Martin;La Villette";
   begin
      for I in 1 .. 12 loop
         declare
            N : constant String := World.Meta_Item ("boats", Paris_Moorings, I);
         begin
            exit when N = "";
         for L of World.Landmarks.all loop
            if To_String (L.Name) = N then
               declare
                  T     : Car;
                  Found : Boolean := False;
               begin
                  T.Kind := Speedboat;
                  Search :
                  for R in 0 .. 60 loop
                     for K in 0 .. 23 loop
                        T.X := L.X + Cos (Float (K) * Pi / 12.0) * Float (R) * 3.0;
                        T.Y := L.Y + Sin (Float (K) * Pi / 12.0) * Float (R) * 3.0;
                        if World.Cell (T.X, T.Y) = 2 then
                           --  moored: parallel to a quay that is within reach
                           for H in 0 .. 11 loop
                              T.A := Float (H) * Pi / 6.0;
                              if Fits (T)
                                and then (World.Land (T.X - Sin (T.A) * 3.4, T.Y + Cos (T.A) * 3.4)
                                          or else World.Land (T.X + Sin (T.A) * 3.4, T.Y - Cos (T.A) * 3.4))
                                and then No_Car_Overlap (T.X, T.Y, 6.0)
                              then
                                 Found := True;
                                 exit Search;
                              end if;
                           end loop;
                        end if;
                     end loop;
                  end loop Search;
                  if Found then
                     declare
                        CI : constant Car_Ref := Alloc_Car (Speedboat, T.X, T.Y, T.A);
                     begin
                        if CI /= 0 then
                           Cars (CI).Keep := True;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end loop;
         end;
      end loop;
   end Moor_Boats;

   procedure Become_Traffic (CI : Car_Ref) is
      C : Car renames Cars (CI);
      N : constant Integer := Nearest (Car_Graph, C.X, C.Y, 80.0);
   begin
      C.Siren := False;
      if N < 0 then
         C.Driver := No_Driver;
         return;
      end if;
      C.AI := (Mode => Traffic, Len => 1, Idx => 1, Lane => 2.0, Cruise => 10.0, others => <>);
      C.AI.Path (1) := N;
   end Become_Traffic;

   ------------------------------------------------------------------ cops on foot
   procedure Cop_Move (P : in out Ped; TX, TY, Spd, DT : Float) is
      Ang : Float := Arctan (TY - P.Y, TX - P.X);
      Sgn : constant Float := (if P.Serial mod 2 = 1 then 1.0 else -1.0);
      Offs : constant array (1 .. 7) of Float := (0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8);
   begin
      for O of Offs loop
         declare
            A : constant Float := Ang + O * Sgn;
         begin
            if not World.Blocked (P.X + Cos (A), P.Y + Sin (A)) then
               Ang := A;
               exit;
            end if;
         end;
      end loop;
      P.A := Ang;
      Ped_Move_By (P, Cos (Ang) * Spd * DT, Sin (Ang) * Spd * DT);
      P.Moving := True;
   end Cop_Move;

   procedure Update_Cop (I : Ped_Ref; DT : Float) is
      P : Ped renames Peds (I);
   begin
      P.Moving := False;
      P.Shoot_T := P.Shoot_T - DT;
      if Heat < 1.0 or else Mode /= Play then
         declare
            HC : constant Car_Ref := P.Home_Car;
         begin
            if HC /= 0 and then Cars (HC).Active and then Cars (HC).Kind = Police and then not Cars (HC).Dead
              and then Cars (HC).Driver = No_Driver and then HC /= Player_Car
            then
               if Hypot (Cars (HC).X - P.X, Cars (HC).Y - P.Y) < 2.8 then
                  Cars (HC).Driver := AI_Driver;
                  Cars (HC).Deployed := False;
                  Become_Traffic (HC);
                  P.Active := False;     --  climbed back in
                  return;
               end if;
               Cop_Move (P, Cars (HC).X, Cars (HC).Y, 2.2, DT);
            else
               Ped_Wander (P, DT);
            end if;
         end;
         return;
      end if;
      declare
         TX   : constant Float := (if Player_Car /= 0 then Cars (Player_Car).X else PX);
         TY   : constant Float := (if Player_Car /= 0 then Cars (Player_Car).Y else PY);
         D    : constant Float := Hypot (TX - P.X, TY - P.Y);
         Seen : constant Boolean := D < 40.0 and then World.LOS (P.X, P.Y, TX, TY);
      begin
         if Player_Car /= 0 then
            if D < Params (Cars (Player_Car).Kind).Len / 2.0 + 2.2 and then Speed (Cars (Player_Car)) < 1.5 then
               Bust_T := Bust_T + DT;
               if Bust_T > 1.0 then
                  Arrest;
               end if;
            else
               Cop_Move (P, TX, TY, (if D > 6.0 then 4.6 else 3.0), DT);
            end if;
         else
            if D < 1.2 then
               Bust_T := Bust_T + DT;
               if Bust_T > 0.7 then
                  Arrest;
               end if;
            else
               Cop_Move (P, TX, TY, 4.7, DT);
            end if;
         end if;
         if Heat >= 2.0 and then Seen and then D > 3.0 and then D < 30.0 and then P.Shoot_T <= 0.0 then
            P.A := Arctan (TY - P.Y, TX - P.X);
            Fire_Weapon (I, P.X + Cos (P.A) * 0.6, P.Y + Sin (P.A) * 0.6, P.A, 1, 0);
            P.Shoot_T := Rand (0.9, 1.6) - Heat * 0.1;
         end if;
      end;
   end Update_Cop;

   procedure Update_Police (DT : Float) is
      Seen : Boolean := False;
   begin
      Star_Flash := Float'Max (0.0, Star_Flash - DT);
      Bust_T := Float'Max (0.0, Bust_T - DT * 0.5);
      if Heat <= 0.0 then
         Heat := 0.0;
         return;
      end if;
      for C of Cars loop
         if C.Active and then C.Driver = AI_Driver and then C.AI.Mode = Pursuit
           and then Hypot (C.X - PX, C.Y - PY) < 55.0 and then World.LOS (C.X, C.Y, PX, PY)
         then
            Seen := True;
            exit;
         end if;
      end loop;
      if not Seen then
         for P of Peds loop
            if P.Active and then P.Cop and then not P.Dead and then Hypot (P.X - PX, P.Y - PY) < 40.0
              and then World.LOS (P.X, P.Y, PX, PY)
            then
               Seen := True;
               exit;
            end if;
         end loop;
      end if;
      if Seen and then not Secrets.Hidden_In_Crowd then
         Seen_T := 0.0;
      else
         Seen_T := Seen_T + DT;
      end if;
      if Seen_T > 9.0 then
         declare
            Had_Stars : constant Boolean := Heat >= 1.0;
         begin
            Heat := Heat - DT * 0.14;
            if Heat < 1.0 then
               Heat := 0.0;
               if Had_Stars then
                  Say ("You lost the police.", 2.5);
               end if;
               for I in Cars'Range loop
                  if Cars (I).Active and then Cars (I).Driver = AI_Driver and then Cars (I).AI.Mode = Pursuit then
                     Become_Traffic (I);
                  end if;
               end loop;
            end if;
         end;
      end if;
   end Update_Police;

   ------------------------------------------------------------------ pickups
   procedure Scatter_Pickups (N : Natural) is
      Kinds : constant array (1 .. 11) of Pickup_Kind :=
        (Pistol_Ammo, Pistol_Ammo, SMG_Ammo, Shotgun_Ammo, Shotgun_Ammo, Grenade_Box,
         Health, Health, Body_Armor, Cash, Cash);
   begin
      for K in 1 .. N loop
         declare
            Node : constant Natural := Rand_Int (Node_Count (Ped_Graph));
            Kind : constant Pickup_Kind := (if Rand < 0.05 then Rocket_Ammo        --  rockets are rare
                                            else Kinds (1 + Rand_Int (Kinds'Length)));
         begin
            for P of Pickups loop
               if not P.Active then
                  P := (True, Kind, NX (Ped_Graph, Node), NY (Ped_Graph, Node),
                        (if Kind = Cash then 250 else 0), True);
                  exit;
               end if;
            end loop;
         end;
      end loop;
   end Scatter_Pickups;

   procedure Take_Pickup (K : in out Pickup) is
      P : Ped renames Peds (Player);
   begin
      if (K.Kind = Health and then P.HP >= 100.0) or else (K.Kind = Body_Armor and then Armor >= 100.0) then
         return;
      end if;
      K.Active := False;
      Sound.Play (Sound.Pickup);
      case K.Kind is
         when Cash        => Money := Money + K.N; Say ("+" & Euro (K.N) & " " & Cur, 1.0);
         when Pistol_Ammo => Ammo (1) := Ammo (1) + 30; Say ("Pistol +30", 1.5);
            if Weapon = 0 then
               Weapon := 1;
            end if;
         when SMG_Ammo    => Ammo (2) := Ammo (2) + 90; Say ("SMG +90", 1.5); Weapon := 2;
         when Health      => P.HP := 100.0; Say ("Health", 1.5);
         when Body_Armor  => Armor := 100.0; Say ("Body armour", 1.5);
         when Shotgun_Ammo => Ammo (3) := Ammo (3) + 16; Say ("Shotgun +16", 1.5); Weapon := 3;
         when Grenade_Box  => Ammo (4) := Ammo (4) + 5; Say ("Grenades +5", 1.5);
         when Rocket_Ammo  => Ammo (5) := Ammo (5) + 4; Say ("Rocket launcher +4", 2.0); Weapon := 5;
      end case;
   end Take_Pickup;

   ------------------------------------------------------------------ spawning
   function No_Car_Overlap (X, Y, Len : Float) return Boolean is
   begin
      for O of Cars loop
         if O.Active and then Hypot (O.X - X, O.Y - Y) < (Params (O.Kind).Len + Len) / 2.0 + 1.5 then
            return False;
         end if;
      end loop;
      return True;
   end No_Car_Overlap;

   function Spawn_Parked (X, Y : Float; K : Car_Type; Radius : Float) return Car_Ref is
   begin
      for Tries in 1 .. 25 loop
         declare
            N : constant Integer := Nearest (Car_Graph, X + Rand (-Radius, Radius), Y + Rand (-Radius, Radius), 60.0);
         begin
            --  never park at intersections: "beside" one street is the middle of another
            if N >= 0 and then Degree (Car_Graph, N) > 0 and then Undirected_Degree (Car_Graph, N) = 2
              and then Undirected_Degree (Car_Graph, Neighbor (Car_Graph, N, 1)) = 2
            then
               declare
                  M   : constant Natural := Neighbor (Car_Graph, N, 1);
                  DX  : constant Float := NX (Car_Graph, M) - NX (Car_Graph, N);
                  DY  : constant Float := NY (Car_Graph, M) - NY (Car_Graph, N);
                  L   : constant Float := Float'Max (Hypot (DX, DY), 0.001);
                  Off : constant Float := (if Two_Way (N, M) then 4.3 else 2.6);
                  Tmp : Car;
               begin
                  Tmp.Kind := K;
                  Tmp.X := NX (Car_Graph, N) + (-DY / L) * Off;
                  Tmp.Y := NY (Car_Graph, N) + (DX / L) * Off;
                  Tmp.A := Arctan (DY, DX);
                  if Fits (Tmp) and then No_Car_Overlap (Tmp.X, Tmp.Y, Params (K).Len) then
                     return Alloc_Car (K, Tmp.X, Tmp.Y, Tmp.A);
                  end if;
               end;
            end if;
         end;
      end loop;
      return 0;
   end Spawn_Parked;

   function Spawn_Traffic (X, Y : Float; K : Car_Type; M : AI_Mode := Traffic) return Car_Ref is
      N : constant Integer := Nearest (Car_Graph, X, Y, 40.0);
   begin
      if N < 0 or else Degree (Car_Graph, N) = 0 then
         return 0;
      end if;
      declare
         Nb   : constant Natural := Neighbor (Car_Graph, N, 1 + Rand_Int (Degree (Car_Graph, N)));
         DX   : constant Float := NX (Car_Graph, Nb) - NX (Car_Graph, N);
         DY   : constant Float := NY (Car_Graph, Nb) - NY (Car_Graph, N);
         L    : constant Float := Float'Max (Hypot (DX, DY), 0.001);
         Lane : constant Float := (if M = Pursuit then 0.0 else 2.1);
         Off  : constant Float := (if Two_Way (N, Nb) then Lane else 0.0);
         Tmp  : Car;
         CI   : Car_Ref;
      begin
         Tmp.Kind := K;
         Tmp.X := NX (Car_Graph, N) + (-DY / L) * Off;
         Tmp.Y := NY (Car_Graph, N) + (DX / L) * Off;
         Tmp.A := Arctan (DY, DX);
         if not Fits (Tmp) or else not No_Car_Overlap (Tmp.X, Tmp.Y, Params (K).Len) then
            return 0;
         end if;
         CI := Alloc_Car (K, Tmp.X, Tmp.Y, Tmp.A);
         if CI = 0 then
            return 0;
         end if;
         declare
            C : Car renames Cars (CI);
            V : constant Float := (if M = Pursuit then 10.0 else 6.0);
         begin
            C.Driver := AI_Driver;
            C.AI := (Mode => M, Len => 2, Idx => 2, Lane => Lane,
                     Cruise => (if K = Bus then 8.0 else Rand (9.0, 13.0)), others => <>);
            C.AI.Path (1) := N;
            C.AI.Path (2) := Nb;
            C.VX := Cos (C.A) * V;
            C.VY := Sin (C.A) * V;
            C.Siren := M = Pursuit;
         end;
         return CI;
      end;
   end Spawn_Traffic;

   procedure Ring_Point (R0, R1 : Float; X, Y : out Float) is
      A : constant Float := Rand (0.0, 2.0 * Pi);
      R : constant Float := Rand (R0, R1);
   begin
      X := PX + Cos (A) * R;
      Y := PY + Sin (A) * R;
   end Ring_Point;

   procedure Manage_Spawns (DT : Float) is
      R0    : constant Float := View_HD + 15.0;
      R1    : constant Float := R0 + 90.0;
      RKill : constant Float := R1 + 70.0;
      First : constant Boolean := not Populated;
      Traffic_N, Parked_N, Police_N, Peds_N : Natural := 0;
      Budget : Integer;
      X, Y   : Float;
      Dummy  : Car_Ref;
   begin
      for I in Cars'Range loop
         declare
            C : Car renames Cars (I);
         begin
            if C.Active then
               if (C.Sunk and then C.Sink_T > 3.0 and then I /= Player_Car)
                 or else (I /= Player_Car and then not C.Keep
                          and then Hypot (C.X - PX, C.Y - PY) > RKill and then not On_Screen (C.X, C.Y))
               then
                  C.Active := False;
               elsif C.Driver = AI_Driver and then C.AI.Mode = Pursuit and then not Is_Boat (C.Kind) then
                  Police_N := Police_N + 1;
               elsif C.Driver = AI_Driver then
                  Traffic_N := Traffic_N + 1;
               elsif not C.Dead then
                  Parked_N := Parked_N + 1;
               end if;
            end if;
         end;
      end loop;
      for I in Peds'Range loop
         declare
            P : Ped renames Peds (I);
         begin
            if P.Active and then not P.Is_Player and then not P.Keep then
               if (P.Dead and then P.Dead_T > 40.0 and then not On_Screen (P.X, P.Y))
                 or else (Hypot (P.X - PX, P.Y - PY) > Float'Min (RKill, 260.0) and then not On_Screen (P.X, P.Y))
               then
                  P.Active := False;
               elsif not P.Dead and then not P.Cop then
                  Peds_N := Peds_N + 1;
               end if;
            end if;
         end;
      end loop;
      Budget := (if First then 200 else 3);
      while Traffic_N < 34 and then Budget > 0 loop
         Budget := Budget - 1;
         Ring_Point ((if First then 12.0 else R0), R1, X, Y);
         if First or else not On_Screen (X, Y, 10.0) then
            if Spawn_Traffic (X, Y, Mix (1 + Rand_Int (Mix'Length))) /= 0 then
               Traffic_N := Traffic_N + 1;
            end if;
         end if;
      end loop;
      Budget := (if First then 200 else 2);
      while Parked_N < 22 and then Budget > 0 loop
         Budget := Budget - 1;
         Ring_Point ((if First then 8.0 else R0), R1, X, Y);
         if First or else not On_Screen (X, Y, 10.0) then
            if Spawn_Parked (X, Y, Mix (1 + Rand_Int (Mix'Length - 1)), 5.0) /= 0 then
               Parked_N := Parked_N + 1;
            end if;
         end if;
      end loop;
      Budget := (if First then 300 else 4);
      while Peds_N < 75 and then Budget > 0 loop
         Budget := Budget - 1;
         Ring_Point ((if First then 6.0 else Float'Min (R0, 150.0)), Float'Min (R1, 200.0), X, Y);
         if First or else not On_Screen (X, Y, 6.0) then
            declare
               N : constant Integer := Nearest (Ped_Graph, X, Y, 25.0);
            begin
               if N >= 0 and then not World.Blocked (NX (Ped_Graph, N), NY (Ped_Graph, N)) then
                  if Alloc_Ped (NX (Ped_Graph, N), NY (Ped_Graph, N)) /= 0 then
                     Peds_N := Peds_N + 1;
                  end if;
               end if;
            end;
         end if;
      end loop;
      --  police
      declare
         Want : constant array (0 .. 5) of Natural := (0, 1, 3, 4, 6, 8);
      begin
         Police_T := Police_T - DT;
         if Police_N < Want (Stars) and then Police_T <= 0.0 and then Mode = Play then
            Police_T := 1.5 / Float (Natural'Max (1, Stars));
            for K in 1 .. 6 loop
               Ring_Point (Float'Min (R0, 160.0), Float'Min (R1, 240.0), X, Y);
               if not On_Screen (X, Y, 10.0) then
                  Dummy := Spawn_Traffic (X, Y, (if Stars >= 5 and then Rand < 0.4 then Tank else Police), Pursuit);
                  if Dummy /= 0 and then Cars (Dummy).Kind = Tank then
                     Cars (Dummy).Siren := False;
                     Cars (Dummy).Turret := Cars (Dummy).A;
                     Cars (Dummy).Gun_T := 3.0;
                  end if;
                  exit when Dummy /= 0;
               end if;
            end loop;
         end if;
      end;
      Populated := True;
   end Manage_Spawns;

   ------------------------------------------------------------------ missions
   function Find_Spot (Name : String) return Natural is   --  0 if not on this map
   begin
      for I in 1 .. N_Spots loop
         if To_String (Spots (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Spot;

   function Spot_Index (Name : String) return Positive is (Positive'Max (1, Find_Spot (Name)));

   procedure Release_Mission_Entities is
   begin
      if Mis.M_Target /= 0 then
         Peds (Mis.M_Target).Keep := False;
      end if;
      if Mis.M_Car /= 0 then
         Cars (Mis.M_Car).Keep := False;
      end if;
   end Release_Mission_Entities;

   procedure Fail_Mission (Why : String) is
   begin
      if not Has_Mission then
         return;
      end if;
      Release_Mission_Entities;
      Phones (Mis.Phone_Idx).Cool := 10.0;
      Has_Mission := False;
      if Why /= "" then
         Show_Big ("JOB FAILED", Red, 2.5, Why);
         Sound.Play (Sound.Job_Failed);
      end if;
   end Fail_Mission;

   procedure Pass_Mission is
   begin
      Money := Money + Mis.Reward;
      Show_Big ("JOB DONE!", Green, 3.0, "+" & Euro (Mis.Reward) & " " & Cur);
      Sound.Play (Sound.Job_Passed);
      for Ph of Phones loop      --  don't chain straight into a job at a nearby phone
         Ph.Cool := Float'Max (Ph.Cool, 6.0);
      end loop;
      Phones (Mis.Phone_Idx).Cool := 15.0;
      Release_Mission_Entities;
      Has_Mission := False;
      if Money >= 50_000 and then not Won then
         Won := True;
         Win_Delay := 3.2;
      end if;
   end Pass_Mission;

   procedure Start_Mission (Ph : Positive) is
      Far   : array (1 .. N_Spots) of Positive;
      NF    : Natural := 0;
      Dest  : Positive;
      Dist  : Float;
      Kinds : constant array (1 .. 7) of Mission_Kind := (Delivery, Steal, Hit_Job, Escape, Delivery, Steal, Hit_Job);
      K     : Mission_Kind;
   begin
      for I in 1 .. N_Spots loop
         declare
            D : constant Float := Hypot (Spots (I).CX - PX, Spots (I).CY - PY);
         begin
            if D > 500.0 and then D < 1700.0 then
               NF := NF + 1;
               Far (NF) := I;
            end if;
         end;
      end loop;
      Dest := (if NF > 0 then Far (1 + Rand_Int (NF)) else 1 + Rand_Int (N_Spots));
      K := (if Mission_Count = 0 then Delivery else Kinds (1 + Rand_Int (Kinds'Length)));
      Mission_Count := Mission_Count + 1;
      Dist := Hypot (Spots (Dest).CX - PX, Spots (Dest).CY - PY);
      Mis := (Kind => K, Phone_Idx => Ph, Dest => Dest, others => <>);
      case K is
         when Delivery =>
            Mis.TX := Spots (Dest).CX; Mis.TY := Spots (Dest).CY;
            Mis.Has_Timer := True;
            Mis.Timer := Float'Rounding (Dist / 9.0 + 35.0);
            Mis.Reward := Integer (Float'Rounding (Dist * 2.5 / 50.0)) * 50 + 500;
            Say ("PHONE: ""Grab any car and get to " & To_String (Spots (Dest).Name) & ". You have"
                 & Integer'Image (Integer (Mis.Timer)) & " seconds. " & World.Meta ("hurry", "Vite!") & """", 6.0);
         when Steal =>
            declare
               Src : Positive := 1 + Rand_Int (N_Spots);
               CI  : Car_Ref;
            begin
               for T in 1 .. 80 loop
                  exit when Src /= Dest and then Hypot (Spots (Src).CX - PX, Spots (Src).CY - PY) in 250.0 .. 1500.0;
                  Src := 1 + Rand_Int (N_Spots);
               end loop;
               CI := Spawn_Parked (Spots (Src).CX, Spots (Src).CY, Sport, 60.0);
               if CI = 0 then
                  Say ("PHONE: ""...never mind. Call back later.""", 3.0);
                  Phones (Ph).Cool := 5.0;
                  return;
               end if;
               Cars (CI).Keep := True;
               Mis.M_Car := CI;
               Mis.TX := Cars (CI).X; Mis.TY := Cars (CI).Y;
               Mis.Has_Timer := True;
               Mis.Timer := Float'Rounding (Hypot (Cars (CI).X - PX, Cars (CI).Y - PY) / 5.0 + 40.0);
               Mis.Time2 := Float'Rounding (Hypot (Spots (Dest).CX - Cars (CI).X, Spots (Dest).CY - Cars (CI).Y) / 9.0 + 40.0);
               Mis.Reward := 3000;
               Say ("PHONE: ""A collector wants the sports car parked near " & To_String (Spots (Src).Name)
                    & ". Steal it.""", 6.0);
            end;
         when Hit_Job =>
            declare
               S  : Positive := 1 + Rand_Int (N_Spots);
               TI : Ped_Ref;
            begin
               for T in 1 .. 80 loop
                  exit when Hypot (Spots (S).PX - PX, Spots (S).PY - PY) in 300.0 .. 1500.0;
                  S := 1 + Rand_Int (N_Spots);
               end loop;
               TI := Alloc_Ped (Spots (S).PX, Spots (S).PY, Target => True, HP => 140.0);
               if TI = 0 then
                  Phones (Ph).Cool := 5.0;
                  return;
               end if;
               Peds (TI).Walk_Speed := 1.2;
               Peds (TI).Keep := True;
               Mis.M_Target := TI;
               Mis.TX := Peds (TI).X; Mis.TY := Peds (TI).Y;
               Mis.Reward := 4000;
               Mis.Has_Timer := True;
               Mis.Timer := 150.0;
               Say ("PHONE: ""An informant is hanging around " & To_String (Spots (S).Name)
                    & ". Red jacket. Take care of him.""", 6.0);
            end;
         when Escape =>
            Mis.Reward := 6000;
            Mis.Has_Target_Pos := False;
            Heat := Float'Max (Heat, 3.05);
            Seen_T := 0.0;
            Star_Flash := 1.5;
            Say ("PHONE: ""The " & World.Meta ("cops", "flics") & " are onto you! Lose them and I'll make it worth your while.""",
                 6.0);
      end case;
      Has_Mission := True;
      Sound.Play (Sound.Phone_Ring);
      Show_Big ((if K = Escape then "ESCAPE!" else "NEW JOB"), Yellow, 1.5);
   end Start_Mission;

   procedure Update_Mission (DT : Float) is
   begin
      if not Has_Mission then
         if Mode /= Play then
            return;
         end if;
         for I in Phones'Range loop
            if Phones (I).On and then Phones (I).Cool <= 0.0 and then Rand < DT * 0.7
              and then Hypot (Spots (Phones (I).S).PX - PX, Spots (Phones (I).S).PY - PY) < 25.0
            then
               Sound.Play (Sound.Phone_Ring, Att (Spots (Phones (I).S).PX, Spots (Phones (I).S).PY, 30.0));
            end if;
            if Phones (I).On and then Phones (I).Cool <= 0.0 and then Player_Car = 0
              and then Hypot (Spots (Phones (I).S).PX - PX, Spots (Phones (I).S).PY - PY) < 2.5
            then
               Start_Mission (I);
               exit;
            end if;
         end loop;
         return;
      end if;
      if Mis.Has_Timer then
         Mis.Timer := Mis.Timer - DT;
         if Mis.Timer <= 0.0 then
            Fail_Mission ("Out of time!");
            return;
         end if;
      end if;
      case Mis.Kind is
         when Delivery =>
            if Player_Car /= 0
              and then Hypot (Cars (Player_Car).X - Mis.TX, Cars (Player_Car).Y - Mis.TY) < 9.0
            then
               Pass_Mission;
            end if;
         when Steal =>
            declare
               C : Car renames Cars (Mis.M_Car);
               D : Spot renames Spots (Mis.Dest);
            begin
               if Mis.Car_Lost or else not C.Active or else C.Sunk or else C.Dead then
                  Fail_Mission ("The car is wrecked!");
                  return;
               end if;
               if Mis.Stage = 0 and then Player_Car = Mis.M_Car then
                  Mis.Stage := 1;
                  Mis.Timer := Mis.Time2;
                  Say ("Bring it to the garage near " & To_String (D.Name) & ". Don't scratch it!", 5.0);
               end if;
               if Mis.Stage = 1 and then Player_Car = Mis.M_Car then
                  Mis.TX := D.CX; Mis.TY := D.CY;
                  if Hypot (C.X - D.CX, C.Y - D.CY) < 9.0 then
                     Mis.Reward := Mis.Reward + Integer (C.HP / Params (C.Kind).HP * 3000.0);
                     Exit_Car (Force => True);
                     C.Active := False;
                     Mis.M_Car := 0;
                     Pass_Mission;
                  end if;
               else
                  Mis.TX := C.X; Mis.TY := C.Y;
               end if;
            end;
         when Hit_Job =>
            if Mis.Target_Dead then
               Pass_Mission;
            elsif not Peds (Mis.M_Target).Active then
               Fail_Mission ("The target got away.");
            else
               Mis.TX := Peds (Mis.M_Target).X;
               Mis.TY := Peds (Mis.M_Target).Y;
            end if;
         when Escape =>
            if Heat <= 0.0 then
               Pass_Mission;
            end if;
      end case;
   end Update_Mission;

   procedure Nav_Target (Has : out Boolean; X, Y : out Float; Is_Phone : out Boolean) is
      BD : Float := Float'Last;
   begin
      Has := False; X := 0.0; Y := 0.0; Is_Phone := False;
      if Has_Mission then
         if Mis.Has_Target_Pos then
            Has := True; X := Mis.TX; Y := Mis.TY;
         end if;
         return;
      end if;
      for Ph of Phones loop
         if Ph.On and then Ph.Cool <= 0.0 then
            declare
               D : constant Float := Hypot (Spots (Ph.S).PX - PX, Spots (Ph.S).PY - PY);
            begin
               if D < BD then
                  BD := D;
                  Has := True; Is_Phone := True;
                  X := Spots (Ph.S).PX; Y := Spots (Ph.S).PY;
               end if;
            end;
         end if;
      end loop;
   end Nav_Target;

   ------------------------------------------------------------------ player lifecycle
   procedure Spawn_Player (X, Y : Float) is
   begin
      if Player /= 0 then
         Peds (Player).Active := False;
      end if;
      Player := Alloc_Ped (X, Y, Is_Player => True);
      Peds (Player).Keep := True;
      Player_Car := 0;
      Cam_X := X;
      Cam_Y := Y;
   end Spawn_Player;

   procedure Respawn is
      S          : constant Positive := (if Busted then Station else Hospital);
      Old_Pistol : constant Integer := Ammo (1);
   begin
      if Player_Car /= 0 then
         Cars (Player_Car).Driver := No_Driver;
         Player_Car := 0;
      end if;
      Heat := 0.0;
      Bust_T := 0.0;
      for P of Peds loop
         if P.Active and then P.Cop then
            P.Active := False;
         end if;
      end loop;
      for C of Cars loop
         if C.Active and then C.Kind = Police and then (C.Driver /= AI_Driver or else C.AI.Mode = Pursuit) then
            C.Active := False;
         end if;
      end loop;
      Spawn_Player (Spots (S).PX, Spots (S).PY);
      if Busted then
         Ammo := (0 => 1_000_000, 1 => 15, others => 0);
      else
         Ammo := (0 => 1_000_000, 1 => Integer'Max (20, Old_Pistol / 2), others => 0);
      end if;
      Weapon := 1;
      Armor := (if Secrets.Respawn_Armor then 100.0 else 0.0);
      if Secrets.Respawn_SMG then
         Ammo (2) := Integer'Max (Ammo (2), 120);
      end if;
      Mode := Play;
      Say ((if Busted then World.Meta ("station_msg", "Released from the commissariat. Weapons confiscated.")
            else World.Meta ("hospital_msg", "Patched up at the Hotel-Dieu.")), 3.0);
   end Respawn;

   ------------------------------------------------------------------ camera
   procedure Update_Camera (DT : Float) is
      S  : constant Float := Float'Min (Screen_W, Screen_H) / 900.0;
      TZ : Float;
      TX : Float := PX;
      TY : Float := PY;
      K  : constant Float := Float'Min (1.0, DT * 2.5);
   begin
      if Mode = Title then
         TZ := 5.0 * S;
         TX := PX + Cos (Time * 0.05) * 120.0;
         TY := PY + Sin (Time * 0.05) * 90.0;
         Cam_X := TX; Cam_Y := TY;
      else
         if Player_Car /= 0 then
            TZ := (10.0 - Float'Min (1.0, Speed (Cars (Player_Car)) / 32.0) * 5.2) * S
              * (1.0 - 0.45 * Float'Min (1.0, Cars (Player_Car).Z / 50.0));
            declare      --  look ahead, but not so far that a plane leaves the screen
               C : Car renames Cars (Player_Car);
               K : constant Float := 0.9 * Float'Min (1.0, 28.0 / Float'Max (Speed (C), 1.0));
            begin
               TX := TX + C.VX * K;
               TY := TY + C.VY * K;
            end;
         else
            TZ := 12.0 * S;
         end if;
         Cam_X := Cam_X + (TX - Cam_X) * Float'Min (1.0, DT * 5.0);
         Cam_Y := Cam_Y + (TY - Cam_Y) * Float'Min (1.0, DT * 5.0);
      end if;
      TZ := TZ * Cam_Scale;
      if Cam_ZS = 0.0 then
         Cam_ZS := TZ;
      end if;
      Cam_ZS := Cam_ZS + (TZ - Cam_ZS) * K;
      Cam_Z := Cam_ZS;
      Shake := Float'Max (0.0, Shake - DT * 1.8);
      declare
         HW : constant Float := Screen_W / 2.0 / Cam_Z;
         HH : constant Float := Screen_H / 2.0 / Cam_Z;
      begin
         View_X0 := Cam_X - HW; View_X1 := Cam_X + HW;
         View_Y0 := Cam_Y - HH; View_Y1 := Cam_Y + HH;
         View_HD := Hypot (HW, HH);
         View_W := HW * 2.0;
      end;
   end Update_Camera;

   ------------------------------------------------------------------ main update
   procedure Update (DT : Float) is
      Impact : Float;
   begin
      Time := Time + DT;
      if Mode = Play then
         Control_Player (DT);
      elsif Mode = Dead then
         Dead_T := Dead_T - DT;
         if Player_Car /= 0 then
            Cars (Player_Car).Throttle := 0.0;
            Cars (Player_Car).Steer := 0.0;
            Cars (Player_Car).Handbrake := True;
         end if;
         if Dead_T <= 0.0 then
            Respawn;
         end if;
      end if;
      for I in Cars'Range loop
         declare
            C : Car renames Cars (I);
         begin
            if C.Active then
               if C.Driver = AI_Driver then
                  if Is_Boat (C.Kind) then
                     Drive_Boat (I, DT);
                  elsif C.AI.Mode = Pursuit then
                     Drive_Police (I, DT);
                  else
                     Drive_Traffic (I, DT);
                  end if;
               end if;
               if C.Kind = Tank and then not C.Dead and then Speed (C) > 1.0 then
                  for J in Cars'Range loop
                     declare
                        O : Car renames Cars (J);
                     begin
                        if J /= I and then O.Active and then not O.Dead and then O.Kind /= Tank
                          and then Hypot (O.X - C.X, O.Y - C.Y) < (Params (O.Kind).Len + 7.0) * 0.45
                        then
                           Damage (O, 90.0 * DT, (if I = Player_Car then By_Player else By_Cop));
                           if Rand < DT * 8.0 then
                              Particle (O.X, O.Y, Spark);
                           end if;
                        end if;
                     end;
                  end loop;
               end if;
               Update_Car (C, DT, Impact);
               if Impact > 3.0 then
                  On_Crash (I, Impact, C.X, C.Y);
               end if;
               if C.Skidding and then Speed (C) > 3.0 then
                  Add_Skid (C);
               else
                  C.Has_Skid := False;
               end if;
               if C.Sunk then
                  if C.Sink_T = 0.0 then
                     Sound.Play (Sound.Splash, Att (C.X, C.Y, 120.0));
                  end if;
                  C.Sink_T := C.Sink_T + DT;
                  if Rand < 0.3 then
                     Particle (C.X + Rand (-2.0, 2.0), C.Y + Rand (-1.0, 1.0), Splash);
                  end if;
                  if I = Player_Car and then C.Sink_T > 3.0 then
                     Die ("SPLASH!", World.Meta ("splash_msg", "Paris is not a beach."));
                  end if;
               end if;
               if C.Fire_T > 0.0 and then Rand < 0.6 then
                  Particle (C.X + Rand (-1.0, 1.0), C.Y + Rand (-1.0, 1.0), Fire);
               elsif not C.Dead and then C.HP < Params (C.Kind).HP * 0.35 and then Rand < 0.25 then
                  Particle (C.X + Cos (C.A) * Params (C.Kind).Len * 0.35,
                            C.Y + Sin (C.A) * Params (C.Kind).Len * 0.35, Smoke);
               end if;
               if C.Dead and then Rand < 0.05 then
                  Particle (C.X, C.Y, Smoke);
               end if;
            end if;
         end;
      end loop;
      for I in Cars'Range loop
         if Cars (I).Active and then Cars (I).Explode then
            Cars (I).Explode := False;
            Explode (I);
         end if;
      end loop;
      Collide_Cars;
      Update_Police (DT);
      for I in Peds'Range loop
         declare
            P : Ped renames Peds (I);
         begin
            if P.Active then
               if P.Role /= Citizen and then not P.Dead then
                  null;                        --  street characters are moved by Secrets
               elsif P.Cop and then not P.Dead then
                  Update_Cop (I, DT);
               else
                  Ped_Update (P, DT);
               end if;
               if P.Active and then P.Moving then
                  P.Phase := P.Phase + DT * (if P.Mode = Flee or else P.Cop then 13.0 else 8.0);
               end if;
            end if;
         end;
      end loop;
      Collide_Cars_Peds;
      Update_Projectiles (DT);
      Manage_Boats (DT);
      Secrets.Update (DT);
      --  pickups
      if Mode = Play then
         for K of Pickups loop
            if K.Active and then Hypot (K.X - PX, K.Y - PY) < (if Player_Car /= 0 then 2.8 else 1.3) then
               Take_Pickup (K);
            end if;
         end loop;
      end if;
      Pickup_Respawn := Pickup_Respawn - DT;
      if Pickup_Respawn <= 0.0 then
         Pickup_Respawn := 60.0;
         declare
            N : Natural := 0;
         begin
            for K of Pickups loop
               if K.Active and then K.Fixed then
                  N := N + 1;
               end if;
            end loop;
            if N < 36 then
               Scatter_Pickups (1);
            end if;
         end;
      end if;
      --  effects
      for Q of Parts loop
         if Q.Active then
            Q.X := Q.X + Q.VX * DT;
            Q.Y := Q.Y + Q.VY * DT;
            Q.VX := Q.VX * (1.0 - DT * Q.Drag);
            Q.VY := Q.VY * (1.0 - DT * Q.Drag);
            Q.Life := Q.Life - DT;
            if Q.Life <= 0.0 then
               Q.Active := False;
            end if;
         end if;
      end loop;
      for T of Tracers loop
         T.Life := T.Life - DT;
      end loop;
      Msg_T := Msg_T - DT;
      Big_T := Big_T - DT;
      Hurt_Flash := Float'Max (0.0, Hurt_Flash - DT);
      if Win_Delay > 0.0 then
         Win_Delay := Win_Delay - DT;
         if Win_Delay <= 0.0 then
            Show_Big (World.Meta ("win_title", "PARIS IS YOURS"), Yellow, 5.0, "50,000 " & Cur & " earned - keep playing!");
         end if;
      end if;
      --  street banner
      Street_Check := Street_Check - DT;
      if Street_Check <= 0.0 then
         Street_Check := 0.5;
         declare
            S : constant String := World.Street_At (PX, PY);
            N : constant String := (if S = "" then World.District_At (PX, PY) else S);
         begin
            if N /= To_String (Street_Shown) then
               Street_Shown := To_Unbounded_String (N);
               District := To_Unbounded_String (World.District_At (PX, PY));
               Street_T := 3.5;
            end if;
         end;
      end if;
      Street_T := Street_T - DT;
      Update_Mission (DT);
      for Ph of Phones loop
         Ph.Cool := Float'Max (0.0, Ph.Cool - DT);
      end loop;
      Manage_Spawns (DT);
      Update_Camera (DT);
      declare
         Siren : Float := 0.0;
      begin
         for C of Cars loop
            if C.Active and then C.Siren and then not C.Dead and then C.Driver = AI_Driver
              and then C.AI.Mode = Pursuit
            then
               Siren := Float'Max (Siren, Att (C.X, C.Y, 160.0));
            end if;
         end loop;
         Sound.Set_Siren (Siren);
         Sound.Set_Ambience (True);
         Sound.Set_Engine (Player_Car /= 0 and then not Cars (Player_Car).Dead and then Mode /= Title,
                           (if Player_Car /= 0 then Speed (Cars (Player_Car)) else 0.0));
      end;
   end Update;

   Started : Boolean := False;

   function Started_Once return Boolean is (Started);

   procedure Start_Game is
   begin
      Mode := Play;
      Mouse_Down := False;
      --  the key that started the game must not also act in-game (e.g. Enter = get in car)
      Input.End_Frame;
      Gamepad.End_Frame;
      if not Started then
         Say ("Welcome to " & City & ". Find a ringing phone (green on the map) for work.", 6.0);
         Started := True;
      end if;
   end Start_Game;

   procedure Frame (DT : Float) is
      D : constant Float := Float'Min (0.05, DT);
   begin
      if Gamepad.Changed then
         Gamepad.Changed := False;
         if Gamepad.Connected then
            Say ("Controller connected: " & To_String (Gamepad.Name), 3.0);
         else
            Say ("Controller disconnected", 3.0);
            if Mode = Play then
               Mode := Paused;
            end if;
         end if;
      end if;
      if Mode = Title then
         if Hit (K_Enter) or else Hit (K_Space) or else Mouse_Clicked
           or else Gamepad.Hit (Gamepad.Start) or else Gamepad.Hit (Gamepad.A)
         then
            Start_Game;
         end if;
         Update (D);
      else
         if Hit (K_M) or else Gamepad.Hit (Gamepad.Back) then
            Say ((if Sound.Toggle_Mute then "Sound off" else "Sound on"), 1.5);
         end if;
         if Hit (K_P) or else Hit (K_Esc) or else Gamepad.Hit (Gamepad.Start) then
            Mode := (if Mode = Paused then Play elsif Mode = Play then Paused else Mode);
         end if;
         if Mode = Paused then
            Secrets.Paused;
         end if;
         if Mode = Paused and then (Hit (K_Enter) or else Gamepad.Hit (Gamepad.Y)) then
            Mode := Title;      --  back to the title screen (e.g. to change world)
         end if;
         if Mode in Paused | Title then
            Sound.Set_Engine (False, 0.0);
            Sound.Set_Siren (0.0);
            Sound.Set_Ambience (False);
            Sound.Set_Music (0.0);
         else
            declare
               Steps : constant Positive := Positive'Max (1, Integer (Float'Ceiling (D / 0.017)));
            begin
               for I in 1 .. Steps loop
                  Update (D / Float (Steps));
               end loop;
            end;
         end if;
      end if;
      Input.End_Frame;
      Gamepad.End_Frame;
   end Frame;

   ------------------------------------------------------------------ init
   procedure Init is
      Paris_Phones : constant String :=
        "Pont Neuf;Centre Pompidou;Sorbonne;Palais Royal;Le Marais;Saint-Germain-des-Pres;Odeon;"
        & "Les Halles;Montmartre;Bastille;Montparnasse;Trocadero;Republique;Gare du Nord;"
        & "Place d'Italie;Opera";
      function Phone_Name (I : Positive) return String is (World.Meta_Item ("phones", Paris_Phones, I));
   begin
      --  start from a clean slate (Init also runs when switching worlds)
      Cars := (others => <>);
      Peds := (others => <>);
      Parts := (others => <>);
      Tracers := (others => <>);
      Pickups := (others => <>);
      Skid_Head := 0; Skid_Count := 0;
      Blood_Head := 0; Blood_Count := 0;
      Scorch_Head := 0; Scorch_Count := 0;
      Player := 0; Player_Car := 0;
      Weapon := 1; Ammo := (0 => 1_000_000, 1 => 45, others => 0); Projs := (others => <>); Armor := 0.0; Bail_Warn := False;
      Mode := Title; Dead_T := 0.0; Busted := False; Heat := 0.0; Seen_T := 99.0; Bust_T := 0.0;
      Money := 0; Won := False; Win_Delay := 0.0; Police_T := 0.0; Populated := False;
      Has_Mission := False; Mis := (others => <>); Mission_Count := 0; Started := False;
      Cam_ZS := 0.0; Msg_T := 0.0; Big_T := 0.0; Street_T := 0.0; Street_Check := 0.0;
      N_Spots := 0;
      for L of World.Landmarks.all loop
         exit when N_Spots = Spots'Last;
         declare
            Hidden : constant Boolean := Element (L.Name, 1) = '#';      --  a secret's anchor
            PN : constant Integer := (if Hidden then -1 else Nearest (Ped_Graph, L.X, L.Y, 250.0));
            CN : constant Integer := Nearest (Car_Graph, L.X, L.Y, 250.0);
         begin
            if PN >= 0 and then CN >= 0 then
               N_Spots := N_Spots + 1;
               Spots (N_Spots) := (L.Name, NX (Ped_Graph, PN), NY (Ped_Graph, PN),
                                   NX (Car_Graph, CN), NY (Car_Graph, CN));
            end if;
         end;
      end loop;
      Hospital := Spot_Index (World.Meta ("hospital", "Notre-Dame"));
      Station := Spot_Index (World.Meta ("station", "Chatelet"));
      for I in Phones'Range loop
         declare
            S : constant Natural := (if Phone_Name (I) = "" then 0 else Find_Spot (Phone_Name (I)));
         begin
            Phones (I) := (S => Natural'Max (S, 1), Cool => 0.0, On => S > 0);
         end;
      end loop;
      declare
         S : constant Positive := Spot_Index (World.Meta ("start", "Saint-Sulpice"));
         Best_X : Float := Spots (S).PX;
         Best_Y : Float := Spots (S).PY;
         Best_D : Float := 0.0;
      begin
         --  the walkable point near the square that is farthest from any road
         for I in 0 .. Node_Count (Ped_Graph) - 1 loop
            declare
               X : constant Float := NX (Ped_Graph, I);
               Y : constant Float := NY (Ped_Graph, I);
            begin
               if Hypot (X - Spots (S).PX, Y - Spots (S).PY) < 45.0 and then not World.Blocked (X, Y) then
                  declare
                     C : constant Integer := Nearest (Car_Graph, X, Y, 40.0);
                     D : constant Float := (if C < 0 then 40.0
                                            else Hypot (NX (Car_Graph, C) - X, NY (Car_Graph, C) - Y));
                  begin
                     if D > Best_D then
                        Best_D := D; Best_X := X; Best_Y := Y;
                     end if;
                  end;
               end if;
            end;
         end loop;
         Spawn_Player (Best_X, Best_Y);
      end;
      Scatter_Pickups (36);
      Moor_Boats;
      Secrets.Init;
      Pickup_Respawn := 60.0;
      Update_Camera (0.016);
   end Init;

   procedure Traffic_Report is
      procedure Put_Line (S : String) renames Ada.Text_IO.Put_Line;
      function I (F : Float) return String is (Integer'Image (Integer (F)));
   begin
      for CI in Cars'Range loop
         declare
            C : Car renames Cars (CI);
         begin
            if C.Active and then C.Driver = AI_Driver and then C.AI.Mode = Traffic and then Speed (C) < 0.5 then
               declare
                  Gap : constant Float := Obstacle_Ahead (CI, 20.0);
                  B   : constant Car_Ref := C.AI.Blocked_By;
                  TX, TY : Float;
               begin
                  AI_Target (C, 5.0, TX, TY);
                  Put_Line ("  " & C.Kind'Image & " at" & I (C.X) & "," & I (C.Y)
                            & " gap" & I (Gap * 10.0) & "dm wait" & I (C.AI.Wait_T)
                            & " tgt-angle" & I (Ang_Diff (C.A, Arctan (TY - C.Y, TX - C.X)) * 57.3)
                            & " thr" & I (C.Throttle * 100.0)
                            & (if B /= 0 then " blocked by " & Cars (B).Kind'Image & " "
                               & Cars (B).Driver'Image & (if Cars (B).Dead then " WRECK" else "")
                               & " speed" & I (Speed (Cars (B)))
                               & (if Cars (B).Driver = AI_Driver and then Cars (B).AI.Blocked_By = CI
                                  then " (MUTUAL)" else "")
                               else " (no car ahead)"));
               end;
            end if;
         end;
      end loop;
   end Traffic_Report;

   --  helicopter and plane
   procedure Air_Test is
      procedure Put_Line (S : String) renames Ada.Text_IO.Put_Line;
      procedure Check (Name : String; Ok : Boolean) is
      begin
         Put_Line ("air: " & Name & " passed=" & Boolean'Image (Ok));
      end Check;
      procedure Snap (Name : String) is
      begin
         if Secrets.Shot /= null then
            Secrets.Shot (Name);
         end if;
      end Snap;
      procedure Pad (RT, LT, LX : Float; Land : Boolean := False) is
      begin
         Gamepad.RT := RT; Gamepad.LT := LT; Gamepad.LX := LX;
         Gamepad.Down (Gamepad.A) := Land;
         Frame (1.0 / 60.0);
      end Pad;
      --  an aircraft of kind K on open ground near (X, Y)
      function Place (K : Car_Type; X, Y : Float) return Car_Ref is
         T : Car;
      begin
         T.Kind := K;
         for R in 0 .. 40 loop
            for D in 0 .. 15 loop
               T.X := X + Cos (Float (D) * Pi / 8.0) * Float (R) * 3.0;
               T.Y := Y + Sin (Float (D) * Pi / 8.0) * Float (R) * 3.0;
               T.A := Float (D) * Pi / 8.0;
               if Fits (T) and then No_Car_Overlap (T.X, T.Y, 12.0) then
                  return Alloc_Car (K, T.X, T.Y, T.A);
               end if;
            end loop;
         end loop;
         return 0;
      end Place;
      --  land run along heading A from (X, Y): how far before something is in the way
      function Runway (X, Y, A : Float) return Float is
         D : Float := 0.0;
      begin
         while D < 400.0 loop
            exit when not (World.Land (X + Cos (A) * D, Y + Sin (A) * D)
                           and then World.Land (X + Cos (A) * D - Sin (A) * 2.0, Y + Sin (A) * D + Cos (A) * 2.0)
                           and then World.Land (X + Cos (A) * D + Sin (A) * 2.0, Y + Sin (A) * D - Cos (A) * 2.0));
            D := D + 2.0;
         end loop;
         return D;
      end Runway;
      H : Car_Ref;
   begin
      Clear_Wanted;
      if Player_Car /= 0 then
         Exit_Car (Force => True);
      end if;
      Peds (Player).X := Spots (1).PX; Peds (Player).Y := Spots (1).PY;
      Peds (Player).HP := 100.0;
      H := Place (Helicopter, PX, PY);
      Check ("a helicopter fits somewhere", H /= 0);
      if H /= 0 then
         declare
            C      : Car renames Cars (H);
            X0, Y0 : Float;
            Ok     : Boolean;
         begin
            X0 := C.X; Y0 := C.Y;
            Place_Beside (H, Ok);
            Enter_Car;
            Check ("board the helicopter", Player_Car = H);
            for I in 1 .. 420 loop                 --  climb, turning on the spot
               Pad (0.0, 0.0, 0.4);
            end loop;
            Check ("helicopter climbs (" & Integer'Image (Integer (C.Z)) & " m)", C.Z > 20.0);
            Snap ("helicopter");
            for I in 1 .. 240 loop                 --  fly over the rooftops
               Pad (1.0, 0.0, 0.0);
            end loop;
            Check ("helicopter flies over buildings (" & Integer'Image (Integer (Hypot (C.X - X0, C.Y - Y0)))
                   & " m away)", Hypot (C.X - X0, C.Y - Y0) > 40.0 and then not C.Dead);
            Exit_Car;
            Check ("no getting out in mid-air", Player_Car = H);
            for I in 1 .. 1500 loop                --  fly back and land where it took off
               declare
                  D    : constant Float := Hypot (X0 - C.X, Y0 - C.Y);
                  Diff : constant Float := Ang_Diff (C.A, Arctan (Y0 - C.Y, X0 - C.X));
                  VF   : constant Float := Fwd_Speed (C);
               begin
                  if D < 3.0 and then abs VF < 2.0 then
                     Pad (0.0, 0.0, 0.0, Land => True);
                  else
                     Pad ((if abs Diff < 0.4 and then VF < Float'Min (30.0, D * 0.7) then 1.0 else 0.0),
                          (if VF > Float'Min (30.0, D * 0.7) + 2.0 or else (D < 3.0 and then VF > 0.5) then 1.0 else 0.0),
                          Clamp (Diff * 2.0, -1.0, 1.0));
                  end if;
                  exit when C.Z < 0.05 and then D < 4.0;
               end;
            end loop;
            Check ("helicopter lands safely", C.Z < 0.05 and then not C.Dead and then C.Fire_T <= 0.0);
            Pad (0.0, 0.0, 0.0);
            Exit_Car;
            Check ("step out after landing", Player_Car = 0);
            C.Active := False;
         end;
      end if;
      --  plane: find a long straight road, take off along it
      declare
         Best_D : Float := 0.0;
         BX, BY, BA : Float := 0.0;
      begin
         for N in 0 .. Node_Count (Car_Graph) - 1 loop
            exit when Best_D >= 300.0;
            if N mod 7 = 0 then
               for K in 0 .. 11 loop
                  declare
                     A : constant Float := Float (K) * Pi / 6.0;
                     D : constant Float := Runway (NX (Car_Graph, N), NY (Car_Graph, N), A);
                  begin
                     if D > Best_D then
                        Best_D := D; BX := NX (Car_Graph, N); BY := NY (Car_Graph, N); BA := A;
                     end if;
                  end;
               end loop;
            end if;
         end loop;
         Put_Line ("air: longest runway found" & Integer'Image (Integer (Best_D)) & " m");
         for C of Cars loop                         --  clear the runway
            if C.Active and then abs Ang_Diff (BA, Arctan (C.Y - BY, C.X - BX)) < 0.3
              and then Hypot (C.X - BX, C.Y - BY) < Best_D
            then
               C.Active := False;
            end if;
         end loop;
         H := Alloc_Car (Plane, BX, BY, BA);
         if H /= 0 then
            declare
               C : Car renames Cars (H);
            begin
               Peds (Player).X := BX - Sin (BA) * 3.0; Peds (Player).Y := BY + Cos (BA) * 3.0;
               Enter_Car;
               Check ("board the plane", Player_Car = H);
               for I in 1 .. 900 loop
                  Pad (1.0, 0.0, 0.0);
                  exit when C.Z > 25.0 or else C.Dead;
               end loop;
               Check ("plane takes off (" & Integer'Image (Integer (C.Z)) & " m up)", C.Z > 5.0 and then not C.Dead);
               Snap ("plane");
               for I in 1 .. 120 loop
                  Pad (0.0, 1.0, 0.3);              --  throttle back, turn: it must not stall
               end loop;
               Check ("plane stays above stall speed", Fwd_Speed (C) >= 23.9 and then C.Z > 5.0);
               Exit_Car (Force => True);
               C.Active := False;
            end;
         end if;
      end;
      Gamepad.RT := 0.0; Gamepad.LT := 0.0; Gamepad.LX := 0.0; Gamepad.Down (Gamepad.A) := False;
   end Air_Test;

   --  boats: the grid's bridges, moored speedboats, driving on the river, river police
   procedure Boats_Test is
      procedure Put_Line (S : String) renames Ada.Text_IO.Put_Line;
      procedure Run (Sec : Float) is
      begin
         for I in 1 .. Integer (Sec * 60.0) loop
            Frame (1.0 / 60.0);
         end loop;
      end Run;
      procedure Check (Name : String; Ok : Boolean) is
      begin
         Put_Line ("boats: " & Name & " passed=" & Boolean'Image (Ok));
      end Check;
      procedure Snap (Name : String) is
      begin
         if Secrets.Shot /= null then
            Secrets.Shot (Name);
         end if;
      end Snap;
      Bridges, Moored : Natural := 0;
      Boat : Car_Ref := 0;
   begin
      Clear_Wanted;
      if Player_Car /= 0 then
         Exit_Car (Force => True);
      end if;
      for R of World.Roads.all loop
         if R.Bridge and then R.Kind = World.Car_Road and then R.P.Count >= 2 then
            declare
               M : constant Natural := R.P.First + 2 * (R.P.Count / 2);
            begin
               if World.Cell (World.Coords (M), World.Coords (M + 1)) = 3 then
                  Bridges := Bridges + 1;
               end if;
            end;
         end if;
      end loop;
      Check ("bridges over the river are land and water at once (" & Bridges'Image & ")", Bridges > 0);
      --  a boat parked under a bridge, across the river (only for the screenshot)
      if Secrets.Shot /= null then
         for R of World.Roads.all loop
            if R.Bridge and then R.Kind = World.Car_Road and then R.P.Count >= 2 then
               declare
                  M  : constant Natural := R.P.First + 2 * (R.P.Count / 2);
                  X  : constant Float := World.Coords (M);
                  Y  : constant Float := World.Coords (M + 1);
                  DX : constant Float := World.Coords (M) - World.Coords (M - 2);
                  DY : constant Float := World.Coords (M + 1) - World.Coords (M - 1);
                  B  : Car_Ref;
               begin
                  if World.Cell (X, Y) = 3 and then (DX /= 0.0 or else DY /= 0.0) then
                     B := Alloc_Car (Tourboat, X, Y, Arctan (DY, DX) + Pi / 2.0);
                     if B /= 0 then
                        Cars (B).Keep := True;
                        Peds (Player).X := X + 12.0; Peds (Player).Y := Y;
                        Cam_X := X; Cam_Y := Y;
                        for I in 1 .. 30 loop
                           Frame (1.0 / 60.0);
                        end loop;
                        Secrets.Shot ("under_bridge");
                        Cars (B).Active := False;
                     end if;
                     exit;
                  end if;
               end;
            end if;
         end loop;
      end if;
      for I in Cars'Range loop
         if Cars (I).Active and then Cars (I).Kind = Speedboat and then Cars (I).Driver = No_Driver then
            Moored := Moored + 1;
            Boat := I;
         end if;
      end loop;
      Check ("speedboats moored at the quays (" & Moored'Image & ")", Moored > 0);
      if Boat = 0 then
         return;
      end if;
      --  step aboard from the quay
      declare
         C  : Car renames Cars (Boat);
         Ok : Boolean;
      begin
         Place_Beside (Boat, Ok);
         Check ("a quay next to the moored boat", Ok);
         Peds (Player).HP := 100.0;
         Enter_Car;
         Check ("board the speedboat", Player_Car = Boat);
         Run (0.3);
         Snap ("speedboat");
         Exit_Car;
         Check ("step back onto the quay", Player_Car = 0 and then World.Land (PX, PY));
         Enter_Car;
         --  out on the river: full throttle, steering along the channel
         declare
            X0 : constant Float := C.X;
            Y0 : constant Float := C.Y;
         begin
            for I in 1 .. 360 loop
               Gamepad.RT := 1.0;
               declare
                  Best : Float := C.A;
                  BF   : Float := 0.0;
               begin
                  for K in -4 .. 4 loop
                     declare
                        F : constant Float := Feeler (C.X, C.Y, C.A + Float (K) * 0.3, 60.0) - abs Float (K) * 2.0;
                     begin
                        if F > BF then
                           BF := F; Best := C.A + Float (K) * 0.3;
                        end if;
                     end;
                  end loop;
                  Gamepad.LX := Clamp (Ang_Diff (C.A, Best) * 2.0, -1.0, 1.0);
               end;
               Frame (1.0 / 60.0);
            end loop;
            Gamepad.RT := 0.0; Gamepad.LX := 0.0;
            Check ("drive the speedboat (" & Integer'Image (Integer (Hypot (C.X - X0, C.Y - Y0))) & " m)",
                   Hypot (C.X - X0, C.Y - Y0) > 30.0 and then not C.Sunk and then World.Navigable (C.X, C.Y));
            Snap ("speedboat_river");
         end;
      end;
      --  wanted on the water: the river police come
      declare
         Cops, Tours : Natural := 0;
      begin
         for T in 1 .. 25 loop
            Heat := 2.5; Seen_T := 0.0;
            Peds (Player).HP := 100.0;
            Cars (Boat).HP := Params (Speedboat).HP;
            Run (1.0);
            Cops := 0; Tours := 0;
            for C of Cars loop
               if C.Active and then C.Kind = Police_Boat and then C.AI.Mode = Pursuit then
                  Cops := Cops + 1;
               elsif C.Active and then C.Kind = Tourboat then
                  Tours := Tours + 1;
               end if;
            end loop;
            exit when Cops > 0 and then Tours > 0;
         end loop;
         Check ("river police give chase (" & Cops'Image & ")", Cops > 0);
         Check ("bateaux-mouches on the river (" & Tours'Image & ")", Tours > 0);
         Snap ("river_police");
      end;
      Clear_Wanted;
   end Boats_Test;

   --  weapons and special vehicles, checked one by one in a quiet spot
   procedure Weapons_Test is
      procedure Put_Line (S : String) renames Ada.Text_IO.Put_Line;
      procedure Run (Sec : Float) is
      begin
         for I in 1 .. Integer (Sec * 60.0) loop
            Frame (1.0 / 60.0);
         end loop;
      end Run;
      procedure Check (Name : String; Ok : Boolean) is
      begin
         Put_Line ("weapons: " & Name & " passed=" & Boolean'Image (Ok));
      end Check;
      procedure Snap (Name : String) is
      begin
         if Secrets.Shot /= null then
            Secrets.Shot (Name);
         end if;
      end Snap;
      --  a free spot D metres from the player in direction A, with a clear line of fire
      function Target_Car (K : Car_Type; D : Float) return Car_Ref is
      begin
         for Try in 0 .. 15 loop
            declare
               A  : constant Float := Float (Try) * Pi / 8.0;
               X  : constant Float := PX + Cos (A) * D;
               Y  : constant Float := PY + Sin (A) * D;
               CI : Car_Ref;
            begin
               if World.LOS (PX, PY, X, Y) and then not World.Blocked (X, Y) then
                  CI := Alloc_Car (K, X, Y, A + Pi / 2.0);
                  if CI /= 0 then
                     if Fits (Cars (CI)) then
                        Peds (Player).A := A;
                        return CI;
                     end if;
                     Cars (CI).Active := False;
                  end if;
               end if;
            end;
         end loop;
         return 0;
      end Target_Car;
      CI : Car_Ref;
   begin
      Clear_Wanted;
      Mode := Play;
      if Player_Car /= 0 then
         Exit_Car (Force => True);
      end if;
      Peds (Player).HP := 100.0;
      --  move somewhere open: the first Spot
      Peds (Player).X := Spots (1).CX; Peds (Player).Y := Spots (1).CY;
      for C of Cars loop
         if C.Active and then Hypot (C.X - PX, C.Y - PY) < 30.0 then
            C.Active := False;
         end if;
      end loop;
      Ammo := (0 => 1_000_000, 1 => 50, 2 => 50, 3 => 20, 4 => 5, 5 => 5);
      --  shotgun: a parked car 8 m away takes pellet damage
      CI := Target_Car (Sedan, 8.0);
      if CI /= 0 then
         declare
            HP0 : constant Float := Cars (CI).HP;
         begin
            Weapon := 3;
            Fire_Weapon (Player, PX, PY, Peds (Player).A, 3, 0);
            Check ("shotgun hits", Cars (CI).HP < HP0 and then Ammo (3) = 19);
         end;
         Cars (CI).Active := False;
      end if;
      --  rocket: wrecks a car 20 m away
      CI := Target_Car (Sedan, 20.0);
      if CI /= 0 then
         Fire_Weapon (Player, PX + Cos (Peds (Player).A) * 0.6, PY + Sin (Peds (Player).A) * 0.6,
                      Peds (Player).A, 5, 0);
         Run (0.2);
         Snap ("rocket");
         Run (1.3);
         Check ("rocket destroys a car", Cars (CI).Dead);
         Cars (CI).Active := False;
      end if;
      --  grenade: thrown 10 m (the fuse is about 2 s)
      CI := Target_Car (Compact, 10.0);
      if CI /= 0 then
         Launch (Grenade, PX, PY, Peds (Player).A, By_Player, Player, 0, 10.0);
         Run (2.0);
         Snap ("grenade_blast");
         Run (1.5);
         Check ("grenade wrecks a car", Cars (CI).Dead or else Cars (CI).HP < 0.0);
         Cars (CI).Active := False;
      end if;
      Clear_Wanted;
      --  tank: steal it, the stars jump, a shell wrecks a car
      CI := Target_Car (Tank, 9.0);
      if CI /= 0 then
         declare
            T : constant Car_Ref := CI;
         begin
            Peds (Player).X := Cars (T).X + Cos (Cars (T).A + Pi / 2.0) * 2.6;
            Peds (Player).Y := Cars (T).Y + Sin (Cars (T).A + Pi / 2.0) * 2.6;
            Enter_Car;
            Check ("tank: stealing it gives 4 stars", Player_Car = T and then Stars >= 4);
            Run (0.5);
            Snap ("tank");
            Clear_Wanted;
            CI := Target_Car (Van, 22.0);
            if CI /= 0 then
               Cars (T).Turret := Arctan (Cars (CI).Y - Cars (T).Y, Cars (CI).X - Cars (T).X);
               Launch (Shell, Cars (T).X + Cos (Cars (T).Turret) * 4.2, Cars (T).Y + Sin (Cars (T).Turret) * 4.2,
                       Cars (T).Turret, By_Player, Player, T);
               Run (0.6);
               Snap ("tank_shot");
               Run (0.4);
               Check ("tank shell destroys a van", Cars (CI).Dead);
               Cars (CI).Active := False;
            end if;
            Exit_Car (Force => True);
            Cars (T).Active := False;
         end;
      end if;
      Clear_Wanted;
      --  army: at five stars tanks join the police
      Heat := 5.5; Seen_T := 0.0;
      declare
         Tanks : Natural := 0;
      begin
         for Try in 1 .. 30 loop
            Run (1.0);
            Heat := 5.5; Seen_T := 0.0;
            Peds (Player).HP := 100.0;
            Tanks := 0;
            for C of Cars loop
               if C.Active and then C.Kind = Tank and then C.Driver = AI_Driver then
                  Tanks := Tanks + 1;
               end if;
            end loop;
            exit when Tanks > 0;
         end loop;
         Check ("five stars bring the army", Tanks > 0);
         for C of Cars loop
            if C.Active and then C.Kind = Tank and then C.Driver = AI_Driver then
               Peds (Player).X := C.X + 15.0; Peds (Player).Y := C.Y;
               exit;
            end if;
         end loop;
         Run (0.5);
         Snap ("army");
      end;
      Clear_Wanted;
      --  scooters ride in traffic
      declare
         N, Moving : Natural := 0;
      begin
         Run (20.0);
         for C of Cars loop
            if C.Active and then C.Kind = Scooter and then C.Driver = AI_Driver then
               N := N + 1;
               if Speed (C) > 1.0 then
                  Moving := Moving + 1;
               end if;
            end if;
         end loop;
         Check ("scooters in traffic (" & N'Image & "," & Moving'Image & " moving)", N > 0);
         for C of Cars loop
            if C.Active and then C.Kind = Scooter and then C.Driver = AI_Driver then
               Peds (Player).X := C.X + 6.0; Peds (Player).Y := C.Y;
               exit;
            end if;
         end loop;
         Run (0.5);
         Snap ("scooter");
      end;
      Boats_Test;
      Air_Test;
   end Weapons_Test;

   procedure Self_Test is
      procedure Put_Line (S : String) renames Ada.Text_IO.Put_Line;
      procedure Run (Sec : Float) is
      begin
         for I in 1 .. Integer (Sec * 60.0) loop
            Frame (1.0 / 60.0);
         end loop;
      end Run;
      procedure Get (K : Mission_Kind) is
      begin
         for Try in 1 .. 200 loop
            if Has_Mission then
               Fail_Mission ("");
            end if;
            Heat := 0.0;
            Phones (1).Cool := 0.0;
            Start_Mission (1);
            exit when Has_Mission and then Mis.Kind = K;
         end loop;
      end Get;
      M0 : Integer;
   begin
      Mode := Play;
      Run (1.0);
      Mission_Count := 1;
      --  delivery
      Get (Delivery);
      M0 := Money;
      declare
         CI : Car_Ref := Spawn_Parked (PX, PY, Sedan, 80.0);
      begin
         for Try in 1 .. 10 loop
            exit when CI /= 0;
            CI := Spawn_Parked (PX, PY, Sedan, 150.0);
         end loop;
         if CI = 0 then
            Put_Line ("delivery: could not park a test car");
            return;
         end if;
         Peds (Player).X := Cars (CI).X; Peds (Player).Y := Cars (CI).Y;
         Enter_Car;
         Cars (CI).X := Mis.TX; Cars (CI).Y := Mis.TY;
         Run (0.2);
         Put_Line ("delivery: in car=" & Boolean'Image (Player_Car = CI) & " passed="
                   & Boolean'Image (not Has_Mission) & " reward=" & Integer'Image (Money - M0));
         Exit_Car (Force => True);
      end;
      --  steal
      Get (Steal);
      M0 := Money;
      declare
         CI : constant Car_Ref := Mis.M_Car;
      begin
         Peds (Player).X := Cars (CI).X; Peds (Player).Y := Cars (CI).Y;
         Enter_Car;
         Run (0.1);
         Put_Line ("steal: stage after entering=" & Natural'Image (Mis.Stage));
         Cars (CI).X := Spots (Mis.Dest).CX; Cars (CI).Y := Spots (Mis.Dest).CY;
         Cars (CI).VX := 0.0; Cars (CI).VY := 0.0;
         Run (0.2);
         Put_Line ("steal: passed=" & Boolean'Image (not Has_Mission) & " on foot="
                   & Boolean'Image (Player_Car = 0) & " reward=" & Integer'Image (Money - M0));
      end;
      --  hit
      Get (Hit_Job);
      M0 := Money;
      Run (1.0);
      Kill_Ped (Mis.M_Target, By_Player);
      Run (0.1);
      Put_Line ("hit: passed=" & Boolean'Image (not Has_Mission) & " reward=" & Integer'Image (Money - M0)
                & " stars=" & Natural'Image (Stars));
      --  escape: hide far away from everything
      Get (Escape);
      M0 := Money;
      Put_Line ("escape: stars at start=" & Natural'Image (Stars));
      for I in 1 .. 90 loop
         Peds (Player).X := Spots (Spot_Index ("Arts et Metiers")).PX;
         Peds (Player).Y := Spots (Spot_Index ("Arts et Metiers")).PY;
         for C of Cars loop
            if C.Active and then C.Driver = AI_Driver and then C.AI.Mode = Pursuit then
               C.Active := False;     --  keep the cops away for this test
            end if;
         end loop;
         for P of Peds loop
            if P.Active and then P.Cop then
               P.Active := False;
            end if;
         end loop;
         Run (1.0);
         exit when not Has_Mission;
      end loop;
      Put_Line ("escape: passed=" & Boolean'Image (not Has_Mission) & " reward=" & Integer'Image (Money - M0)
                & " stars=" & Natural'Image (Stars) & " mode=" & Mode'Image);
      Weapons_Test;
   end Self_Test;

end Game;
