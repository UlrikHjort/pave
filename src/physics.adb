-- ***************************************************************************
--                      PAVÉ - Physics
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
with Util;  use Util;
with World; use World;

package body Physics is

   ------------------------------------------------------------------ palettes
   type Hex_List is array (Positive range <>) of String (1 .. 7);
   Compact_C : constant Hex_List := ("#c0392b", "#e8e2d0", "#2e86c1", "#f1c40f", "#7f8c8d", "#27ae60", "#d35400", "#8e44ad");
   Sedan_C   : constant Hex_List := ("#1c2833", "#566573", "#a93226", "#d0d3d4", "#1f618d", "#145a32", "#6e2c00");
   Sport_C   : constant Hex_List := ("#e30613", "#ffcc00", "#0a0a0a", "#00a2e8", "#ff6a00");
   Taxi_C    : constant Hex_List := ("#1a1a1a", "#2d2d33");
   Van_C     : constant Hex_List := ("#f4f4f4", "#e0e0e0", "#3c5a99");
   Shirts    : constant Hex_List := ("#c0392b", "#2471a3", "#27ae60", "#f39c12", "#8e44ad", "#ecf0f1", "#2c3e50", "#d35400", "#7f8c8d", "#16a085", "#f5b7b1", "#1a1a1a");
   Hairs     : constant Hex_List := ("#1a1009", "#3b2314", "#7a4b26", "#d9b26a", "#a0a0a0", "#5a1f0b", "#111111");
   Skins     : constant Hex_List := ("#f1c9a5", "#e0ac69", "#c68642", "#8d5524", "#ffdbac");

   function Pick (L : Hex_List) return RGB is (Hex (L (L'First + Rand_Int (L'Length))));

   function Car_Color (K : Car_Type) return RGB is
   begin
      case K is
         when Compact => return Pick (Compact_C);
         when Sedan   => return Pick (Sedan_C);
         when Sport   => return Pick (Sport_C);
         when Taxi    => return Pick (Taxi_C);
         when Van     => return Pick (Van_C);
         when Bus     => return Hex ("#2e8b57");
         when Police  => return Hex ("#f5f5f5");
         when Escargot => return Hex ("#7f8f6c");
         when Fournil => return Hex ("#d9b47c");
         when Fusee   => return Hex ("#ff5a1f");
         when Scooter => return Pick (Sport_C);
         when Tank    => return Hex ("#4b5320");
         when Speedboat => return Pick (Sport_C);
         when Tourboat  => return Hex ("#f4f1e8");
         when Police_Boat => return Hex ("#f5f5f5");
         when Helicopter => return Hex ("#c0392b");
         when Plane      => return Hex ("#ecf0f1");
      end case;
   end Car_Color;

   ------------------------------------------------------------------ allocation
   function Alloc_Car (K : Car_Type; X, Y, A : Float) return Car_Ref is
   begin
      for I in Cars'Range loop
         if not Cars (I).Active then
            Serial_Counter := Serial_Counter + 1;
            Cars (I) := (Active => True, Serial => Serial_Counter, Kind => K,
                         X => X, Y => Y, A => A, Color => Car_Color (K),
                         HP => Params (K).HP, Siren => K = Police, Turret => A, others => <>);
            return I;
         end if;
      end loop;
      return 0;
   end Alloc_Car;

   function Alloc_Ped (X, Y : Float;
                       Cop, Is_Player, Target : Boolean := False;
                       HP : Float := 100.0) return Ped_Ref is
   begin
      for I in Peds'Range loop
         if not Peds (I).Active then
            Serial_Counter := Serial_Counter + 1;
            Peds (I) := (Active => True, Serial => Serial_Counter, X => X, Y => Y,
                         A => Rand (0.0, 6.28), HP => HP, Cop => Cop, Is_Player => Is_Player,
                         Target => Target, Armed => Cop,
                         Shirt => (if Cop then Hex ("#1b2d5c") elsif Is_Player then Hex ("#f2d21b")
                                   elsif Target then Hex ("#b0102a") else Pick (Shirts)),
                         Hair => (if Cop then Hex ("#0e1a38") else Pick (Hairs)),
                         Skin => Pick (Skins), Walk_Speed => Rand (1.1, 1.7),
                         Phase => Rand (0.0, 6.0), Lat => Rand (-0.7, 0.7),
                         Shoot_T => Rand (0.5, 1.5), others => <>);
            return I;
         end if;
      end loop;
      return 0;
   end Alloc_Ped;

   ------------------------------------------------------------------ cars
   function Speed (C : Car) return Float is (Hypot (C.VX, C.VY));
   function Fwd_Speed (C : Car) return Float is (C.VX * Cos (C.A) + C.VY * Sin (C.A));

   procedure Damage (C : in out Car; N : Float; By : Culprit) is
   begin
      if C.Dead then
         return;
      end if;
      C.HP := C.HP - N;
      if By /= Nobody then
         C.Last_Hit := By;
      end if;
      if C.HP <= 0.0 and then C.Fire_T = 0.0 then
         C.Fire_T := 3.5;
      end if;
   end Damage;

   procedure Circles (C : Car; Out_C : out Circle_Array; N : out Natural) is
      P    : Car_Params renames Params (C.Kind);
      FX   : constant Float := Cos (C.A);
      FY   : constant Float := Sin (C.A);
      R    : constant Float := P.Wid / 2.0;
      Span : constant Float := P.Len / 2.0 - R;
   begin
      N := Integer'Min (6, Integer'Max (2, Integer (P.Len / P.Wid)));
      for I in 1 .. N loop
         declare
            O : constant Float := -Span + 2.0 * Span * Float (I - 1) / Float (N - 1);
         begin
            Out_C (I) := (C.X + FX * O, C.Y + FY * O, R);
         end;
      end loop;
   end Circles;

   procedure Collide_World (C : in out Car; Impact : out Float) is
      P  : Car_Params renames Params (C.Kind);
      HL : constant Float := P.Len / 2.0;
      HW : constant Float := P.Wid / 2.0;
      AI : constant Boolean := C.Driver = AI_Driver;
      type Pt is record
         X, Y : Float;
      end record;
      Pts : constant array (1 .. 8) of Pt :=
        ((HL, HW), (HL, -HW), (-HL, HW), (-HL, -HW), (HL, 0.0), (-HL, 0.0), (0.0, HW), (0.0, -HW));
      Boat : constant Boolean := Is_Boat (C.Kind);
      function Blk (X, Y : Float) return Boolean is
        (if Boat then not World.Navigable (X, Y) elsif AI then World.Blocked (X, Y) else World.Solid (X, Y));
   begin
      Impact := 0.0;
      for Iter in 1 .. 2 loop
         for Q of Pts loop
            declare
               FX : constant Float := Cos (C.A);
               FY : constant Float := Sin (C.A);
               PX : constant Float := C.X + FX * Q.X - FY * Q.Y;
               PY : constant Float := C.Y + FY * Q.X + FX * Q.Y;
               NX, NY : Float;
               Push   : Float := 0.0;
               VN     : Float;
            begin
               if Blk (PX, PY) then
                  Normal_At (PX, PY, AI, NX, NY, Boat);
                  if NX /= 0.0 or else NY /= 0.0 then
                     while Push < 1.6 and then Blk (PX + NX * Push, PY + NY * Push) loop
                        Push := Push + 0.15;
                     end loop;
                     C.X := C.X + NX * Push;
                     C.Y := C.Y + NY * Push;
                     VN := C.VX * NX + C.VY * NY;
                     if VN < 0.0 then
                        C.VX := (C.VX - 1.35 * VN * NX) * 0.92;
                        C.VY := (C.VY - 1.35 * VN * NY) * 0.92;
                        Impact := Float'Max (Impact, -VN);
                        C.AV := C.AV + ((PX - C.X) * NY - (PY - C.Y) * NX) * VN * 0.04;
                     end if;
                  end if;
               end if;
            end;
         end loop;
      end loop;
      if Impact > 5.0 then
         Damage (C, (Impact - 5.0) * 4.0, Nobody);
      end if;
      if not C.Sunk and then not Boat and then World.Cell (C.X, C.Y) = 2 then
         C.Sunk := True;
         C.Sink_T := 0.0;
      end if;
   end Collide_World;

   --  aircraft. Helicopter: climbs when you throttle, turns on the spot, lands while the
   --  handbrake is held. Plane: taxis like a car, lifts off above 30 m/s, can't fly slower
   --  than 24 m/s, glides down to land while the handbrake is held.
   procedure Update_Air (C : in out Car; DT : Float; Impact : out Float) is
      P      : Car_Params renames Params (C.Kind);
      Driven : constant Boolean := C.Driver /= No_Driver and then not C.Dead;
      Th     : constant Float := (if Driven then C.Throttle else 0.0);
      St     : constant Float := (if Driven then C.Steer else 0.0);
      HB     : constant Boolean := not Driven or else C.Handbrake;
      FX     : constant Float := Cos (C.A);
      FY     : constant Float := Sin (C.A);
      VF     : Float := C.VX * FX + C.VY * FY;
      Was_Up : constant Boolean := C.Z > 0.3;
   begin
      Impact := 0.0;
      if C.Kind = Helicopter then
         declare
            ZT : constant Float :=
              (if HB then 0.0 elsif Th /= 0.0 or else abs St > 0.2 or else C.Z > 0.3 then 45.0 else C.Z);
         begin
            C.Z := C.Z + Clamp (ZT - C.Z, -7.0 * DT, 6.0 * DT);
         end;
         if C.Z > 1.0 then
            VF := VF + Th * P.Acc * DT;
            VF := Clamp (VF * (1.0 - 0.6 * DT), -P.Max * 0.4, P.Max);
            C.AV := St * P.Steer;
         else
            VF := VF * (1.0 - Float'Min (1.0, 6.0 * DT));
            C.AV := (if C.Z > 0.2 then St * P.Steer * 0.5 else 0.0);
         end if;
      else
         if C.Z <= 0.3 then           --  on the ground: taxi like a car
            C.Z := 0.0;
            if Th > 0.0 then
               VF := VF + P.Acc * Th * DT * (1.0 - Float'Max (0.0, VF) / P.Max);
            elsif Th < 0.0 then
               VF := VF - Sign (VF) * Float'Min (abs VF, P.Brake * (-Th) * DT);
            else
               VF := VF - Sign (VF) * Float'Min (abs VF, 1.5 * DT);
            end if;
            if HB then
               VF := VF - Sign (VF) * Float'Min (abs VF, 9.0 * DT);
            end if;
            C.AV := St * P.Steer * Float'Min (1.0, abs VF / 6.0) * (1.0 - Float'Min (0.8, abs VF / 40.0));
            if VF > 30.0 and then Th > 0.3 then
               C.Z := 0.4;                --  lift-off
            end if;
         else                         --  flying: never below stall speed
            VF := VF + (if Th > 0.0 then P.Acc * Th else P.Brake * 0.3 * Th) * DT;
            VF := Clamp (VF * (1.0 - 0.05 * DT), 24.0, P.Max);
            C.AV := St * 0.7;
            C.Z := C.Z + (if HB then -4.0 elsif C.Z < 60.0 then 6.0 else 0.0) * DT;
            C.Z := Float'Max (0.0, C.Z);
         end if;
      end if;
      C.A := C.A + C.AV * DT;
      C.VX := Cos (C.A) * VF;
      C.VY := Sin (C.A) * VF;
      C.X := C.X + C.VX * DT;
      C.Y := C.Y + C.VY * DT;
      C.Skidding := False;
      --  touchdown: open ground is fine, a roof or the river is not
      if Was_Up and then C.Z <= 0.3 then
         C.Z := 0.0;
         if World.Cell (C.X, C.Y) = 2 then
            C.Sunk := True;
            C.Sink_T := 0.0;
         elsif not Fits (C) or else (C.Kind = Helicopter and then abs VF > 12.0) then
            Damage (C, P.HP * 2.0, Nobody);
            C.Fire_T := Float'Min (C.Fire_T, 0.2);
            Impact := 20.0;
         end if;
      end if;
      if C.Z <= 0.3 then
         Collide_World (C, Impact);
      elsif C.X < 0.0 or else C.Y < 0.0 or else C.X > World.W or else C.Y > World.H
        or else not World.In_Bounds (C.X, C.Y)
      then                            --  the edge of the map: turn back
         C.A := C.A + Pi * DT;
         C.X := C.X - C.VX * DT * 2.0;
         C.Y := C.Y - C.VY * DT * 2.0;
      end if;
      if C.Fire_T > 0.0 then
         C.Fire_T := C.Fire_T - DT;
         if C.Fire_T <= 0.0 then
            C.Fire_T := 0.0;
            C.Explode := True;
         end if;
      end if;
   end Update_Air;

   procedure Update_Car (C : in out Car; DT : Float; Impact : out Float) is
      P        : Car_Params renames Params (C.Kind);
      Throttle : Float := C.Throttle;
      Steer    : Float := C.Steer;
      HB       : Boolean := C.Handbrake;
      FX       : constant Float := Cos (C.A);
      FY       : constant Float := Sin (C.A);
      RX       : constant Float := -FY;
      RY       : constant Float := FX;
      VF       : Float := C.VX * FX + C.VY * FY;
      VR       : Float := C.VX * RX + C.VY * RY;
      Eff      : constant Float := (if C.HP < P.HP * 0.25 then 0.6 else 1.0);
      Slip, SP, Grip, St : Float;
   begin
      if Is_Air (C.Kind) then
         Update_Air (C, DT, Impact);
         return;
      end if;
      if C.Dead or else C.Sunk or else C.Driver = No_Driver then
         Throttle := 0.0; Steer := 0.0;
         HB := C.Driver = No_Driver and then not C.Dead;
      end if;
      if Throttle > 0.0 then
         if VF < -0.5 then
            VF := VF + P.Brake * DT * Throttle;
         else
            VF := VF + P.Acc * Eff * Throttle * DT * Float'Max (0.0, 1.0 - Float'Max (0.0, VF) / P.Max);
         end if;
      elsif Throttle < 0.0 then
         if VF > 0.5 then
            VF := VF - P.Brake * DT * (-Throttle);
         elsif VF > -P.Max * 0.3 then
            VF := VF - P.Acc * 0.6 * DT * (-Throttle);
         end if;
      else
         VF := VF - Sign (VF) * Float'Min (abs VF, (if C.Dead then 6.0 else 2.2) * DT);
      end if;
      if HB then
         VF := VF - Sign (VF) * Float'Min (abs VF, 7.0 * DT);
      end if;
      VF := VF * (1.0 - 0.04 * DT);
      Grip := (if HB then 1.3 elsif C.Dead then 6.0 else P.Grip);
      Slip := abs VR;
      VR := VR * Exp (-Grip * DT);
      SP := abs VF;
      St := Steer * P.Steer * Float'Min (1.0, SP / 4.0) * (1.0 - 0.5 * Float'Min (1.0, SP / 45.0)) * Sign (VF);
      C.AV := C.AV + (St * (if HB then 1.45 else 1.0) - C.AV) * Float'Min (1.0, 9.0 * DT);
      if C.Dead then
         C.AV := C.AV * (1.0 - 3.0 * DT);
      end if;
      C.A := C.A + C.AV * DT;
      C.VX := FX * VF + RX * VR;
      C.VY := FY * VF + RY * VR;
      C.X := C.X + C.VX * DT;
      C.Y := C.Y + C.VY * DT;
      C.Skidding := Slip > 3.5 or else (HB and then SP > 6.0)
        or else (Throttle > 0.5 and then SP < 6.0 and then P.Acc > 12.0 and then C.Driver = Player_Driver);
      Collide_World (C, Impact);
      if C.Fire_T > 0.0 then
         C.Fire_T := C.Fire_T - DT;
         if C.Fire_T <= 0.0 then
            C.Fire_T := 0.0;
            C.Explode := True;
         end if;
      end if;
   end Update_Car;

   function Fits (C : Car) return Boolean is
      P  : Car_Params renames Params (C.Kind);
      FX : constant Float := Cos (C.A);
      FY : constant Float := Sin (C.A);
      L  : constant Float := P.Len / 2.0;
      W2 : constant Float := P.Wid / 2.0;
      function Free (LX, LY : Float) return Boolean is
        (if Is_Boat (C.Kind) then World.Navigable (C.X + FX * LX - FY * LY, C.Y + FY * LX + FX * LY)
         else World.Land (C.X + FX * LX - FY * LY, C.Y + FY * LX + FX * LY));
   begin
      return Free (L, W2) and then Free (L, -W2) and then Free (-L, W2)
        and then Free (-L, -W2) and then Free (0.0, 0.0);
   end Fits;

   ------------------------------------------------------------------ peds
   procedure Ped_Move_By (P : in out Ped; DX, DY : Float) is
      R : constant Float := 0.3;
   begin
      if not World.Blocked (P.X + DX + Sign (DX) * R, P.Y) then
         P.X := P.X + DX;
      end if;
      if not World.Blocked (P.X, P.Y + DY + Sign (DY) * R) then
         P.Y := P.Y + DY;
      end if;
   end Ped_Move_By;

   procedure Ped_Wander (P : in out Ped; DT : Float) is
   begin
      if P.Node < 0 then
         P.Node := Nearest (Ped_Graph, P.X, P.Y, 60.0);
         if P.Node < 0 then
            P.Mode := Idle;
            return;
         end if;
      end if;
      declare
         TX : constant Float := NX (Ped_Graph, P.Node) + P.Lat;
         TY : constant Float := NY (Ped_Graph, P.Node) + P.Lat;
         DX : constant Float := TX - P.X;
         DY : constant Float := TY - P.Y;
         D  : constant Float := Hypot (DX, DY);
         S  : constant Float := P.Walk_Speed * DT;
         OX : constant Float := P.X;
         OY : constant Float := P.Y;
      begin
         if D < 0.8 then
            declare
               Deg   : constant Natural := Degree (Ped_Graph, P.Node);
               Opts  : array (1 .. 16) of Natural;
               N     : Natural := 0;
            begin
               for J in 1 .. Deg loop
                  declare
                     Nb : constant Natural := Neighbor (Ped_Graph, P.Node, J);
                  begin
                     if Nb /= P.Prev and then N < Opts'Last then
                        N := N + 1;
                        Opts (N) := Nb;
                     end if;
                  end;
               end loop;
               P.Prev := P.Node;
               if N > 0 then
                  P.Node := Opts (1 + Rand_Int (N));
               elsif Deg > 0 then
                  P.Node := Neighbor (Ped_Graph, P.Node, 1);
               else
                  P.Node := -1;
               end if;
            end;
            return;
         end if;
         P.A := Arctan (DY, DX);
         Ped_Move_By (P, DX / D * S, DY / D * S);
         P.Moving := True;
         if abs (P.X - OX) + abs (P.Y - OY) < S * 0.2 then
            P.Stuck := P.Stuck + DT;
            if P.Stuck > 2.0 then
               P.Node := -1;
               P.Stuck := 0.0;
            end if;
         end if;
      end;
   end Ped_Wander;

   procedure Ped_Flee (P : in out Ped; DT : Float) is
      DX : Float := P.X - P.Flee_X;
      DY : Float := P.Y - P.Flee_Y;
      D  : constant Float := Float'Max (Hypot (DX, DY), 0.001);
   begin
      DX := DX / D; DY := DY / D;
      if World.Blocked (P.X + DX * 1.2, P.Y + DY * 1.2) then
         declare
            S  : constant Float := (if P.Serial mod 2 = 1 then 1.0 else -1.0);
            T  : constant Float := DX;
         begin
            DX := -DY * S;
            DY := T * S;
         end;
      end if;
      P.A := Arctan (DY, DX);
      Ped_Move_By (P, DX * 4.2 * DT, DY * 4.2 * DT);
      P.Moving := True;
      P.Flee_T := P.Flee_T - DT;
      if P.Flee_T <= 0.0 then
         P.Mode := Walk;
         P.Node := -1;
      end if;
   end Ped_Flee;

   procedure Ped_Scare (P : in out Ped; X, Y, T : Float) is
   begin
      if P.Dead or else P.Is_Player or else P.Cop or else P.Role in Mime | Marcher then
         return;              --  mimes and marchers do not scare
      end if;
      P.Role := Citizen;      --  a scared musician stops playing
      P.Mode := Flee;
      P.Flee_X := X; P.Flee_Y := Y; P.Flee_T := T;
   end Ped_Scare;

   procedure Ped_Update (P : in out Ped; DT : Float) is
   begin
      if P.Is_Player then
         return;
      end if;
      P.Moving := False;
      if P.Dead then
         P.Dead_T := P.Dead_T + DT;
         return;
      end if;
      case P.Mode is
         when Flee => Ped_Flee (P, DT);
         when Walk => Ped_Wander (P, DT);
         when Idle => null;
      end case;
   end Ped_Update;

   ------------------------------------------------------------------ driving AI
   procedure Extend_Random (C : in out Car) is
      AI : AI_State renames C.AI;
   begin
      if AI.Idx > 30 then
         declare
            Shift : constant Natural := AI.Idx - 2;
         begin
            AI.Path (1 .. AI.Len - Shift) := AI.Path (Shift + 1 .. AI.Len);
            AI.Len := AI.Len - Shift;
            AI.Idx := AI.Idx - Shift;
         end;
      end if;
      while AI.Len - AI.Idx < 12 and then AI.Len < Max_Path loop
         declare
            Last : constant Natural := AI.Path (AI.Len);
            Prev : constant Integer := (if AI.Len > 1 then AI.Path (AI.Len - 1) else -1);
            Deg  : constant Natural := Degree (Car_Graph, Last);
            Opts : array (1 .. 16) of Natural;
            N    : Natural := 0;
         begin
            exit when Deg = 0;
            for J in 1 .. Deg loop
               declare
                  Nb : constant Natural := Neighbor (Car_Graph, Last, J);
               begin
                  if Nb /= Prev and then N < Opts'Last then
                     N := N + 1;
                     Opts (N) := Nb;
                  end if;
               end;
            end loop;
            AI.Len := AI.Len + 1;
            AI.Path (AI.Len) := (if N > 0 then Opts (1 + Rand_Int (N)) else Neighbor (Car_Graph, Last, 1));
         end;
      end loop;
   end Extend_Random;

   procedure AI_Target (C : in out Car; Look : Float; TX, TY : out Float) is
      AI    : AI_State renames C.AI;
      I     : Positive;
      PX    : Float := C.X;
      PY    : Float := C.Y;
      Remain : Float := Look;
      EA, EB : Natural;
   begin
      while AI.Idx < AI.Len loop
         declare
            N  : constant Natural := AI.Path (AI.Idx);
            NN : constant Natural := AI.Path (AI.Idx + 1);
            X  : constant Float := NX (Car_Graph, N);
            Y  : constant Float := NY (Car_Graph, N);
            SX : constant Float := NX (Car_Graph, NN) - X;
            SY : constant Float := NY (Car_Graph, NN) - Y;
         begin
            if Hypot (X - C.X, Y - C.Y) < 3.5 or else (C.X - X) * SX + (C.Y - Y) * SY > 0.0 then
               AI.Idx := AI.Idx + 1;
            else
               exit;
            end if;
         end;
      end loop;
      I := AI.Idx;
      TX := NX (Car_Graph, AI.Path (I));
      TY := NY (Car_Graph, AI.Path (I));
      EA := (if I > 1 then AI.Path (I - 1) else AI.Path (I));
      EB := AI.Path (I);
      while I <= AI.Len loop
         declare
            X : constant Float := NX (Car_Graph, AI.Path (I));
            Y : constant Float := NY (Car_Graph, AI.Path (I));
            D : constant Float := Hypot (X - PX, Y - PY);
         begin
            if D >= Remain then
               TX := PX + (X - PX) * Remain / D;
               TY := PY + (Y - PY) * Remain / D;
               exit;
            end if;
            Remain := Remain - D;
            PX := X; PY := Y; TX := X; TY := Y;
            EA := AI.Path (I);
            EB := (if I < AI.Len then AI.Path (I + 1) else AI.Path (I));
            I := I + 1;
         end;
      end loop;
      if AI.Lane /= 0.0 and then EA /= EB and then (AI.Lane < 0.0 or else Two_Way (EA, EB)) then
         declare
            DX : constant Float := NX (Car_Graph, EB) - NX (Car_Graph, EA);
            DY : constant Float := NY (Car_Graph, EB) - NY (Car_Graph, EA);
            L  : constant Float := Float'Max (Hypot (DX, DY), 0.001);
         begin
            TX := TX + (-DY / L) * AI.Lane;
            TY := TY + (DX / L) * AI.Lane;
         end;
      end if;
   end AI_Target;

   function Bend (C : Car) return Float is
      AI   : AI_State renames C.AI;
      I    : Positive := AI.Idx;
      Dist : Float := 0.0;
      Turn : Float := 0.0;
   begin
      while I < AI.Len and then Dist < 28.0 loop
         declare
            DX : constant Float := NX (Car_Graph, AI.Path (I + 1)) - NX (Car_Graph, AI.Path (I));
            DY : constant Float := NY (Car_Graph, AI.Path (I + 1)) - NY (Car_Graph, AI.Path (I));
         begin
            if DX /= 0.0 or else DY /= 0.0 then
               Turn := Float'Max (Turn, abs Ang_Diff (C.A, Arctan (DY, DX)));
            end if;
            Dist := Dist + Hypot (DX, DY);
            I := I + 1;
         end;
      end loop;
      return Turn;
   end Bend;

   procedure Steer_To (C : in out Car; TX, TY, Desired, DT : Float) is
      AI  : AI_State renames C.AI;
      D   : constant Float := Ang_Diff (C.A, Arctan (TY - C.Y, TX - C.X));
      FV  : constant Float := Fwd_Speed (C);
      Err : Float;
   begin
      C.Handbrake := False;
      if AI.Rev_T > 0.0 then
         AI.Rev_T := AI.Rev_T - DT;
         C.Throttle := -0.8;
         C.Steer := (if D > 0.0 then -1.0 else 1.0);
         return;
      end if;
      C.Steer := Clamp (D * 2.2, -1.0, 1.0);
      if abs D > 1.9 and then FV < 5.0 then
         C.Throttle := -0.7;
         C.Steer := -Sign (D);
      else
         Err := Desired - FV;
         C.Throttle := (if Err > 0.5 then Clamp (Err / 4.0, 0.25, 1.0)
                        elsif Err < -1.5 then Clamp (Err / 6.0, -1.0, -0.2) else 0.0);
      end if;
      if Desired > 2.0 and then abs FV < 0.7 then
         AI.Stuck_T := AI.Stuck_T + DT;
         if AI.Stuck_T > (if AI.Mode = Pursuit then 1.2 else 3.5) then
            AI.Rev_T := 1.3;
            AI.Stuck_T := 0.0;
         end if;
      else
         AI.Stuck_T := Float'Max (0.0, AI.Stuck_T - DT);
      end if;
   end Steer_To;

end Physics;
