-- ***************************************************************************
--                      PAVÉ - Render
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
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Glib;
with Cairo;        use Cairo;
with Util;         use Util;
with State;        use State;
with Gfx;          use Gfx;
with Physics;
with World_Render;
with World;
with Game;
with Gamepad;
with Maps;
with Secrets;
use type Maps.World_Id;

package body Render is

   Yellow  : constant RGB := (1.0, 0.82, 0.29);
   White   : constant RGB := (1.0, 1.0, 1.0);
   Phone_G : constant RGB := (0.31, 1.0, 0.47);

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   function Blink (Rate : Float) return Boolean is
     (Integer (Float'Floor (Time * Rate)) mod 2 = 1);

   ------------------------------------------------------------------ cars
   --  boats: a pointed hull, drawn instead of the car body
   procedure Draw_Boat (Cr : Cairo_Context; C : Car; Alpha : Float) is
      L    : constant Float := Params (C.Kind).Len;
      Wd   : constant Float := Params (C.Kind).Wid;
      Hull : constant RGB := (if C.Dead then Hex ("#262626") else C.Color);
      procedure Hull_Path (Inset : Float) is
         HL : constant Float := L / 2.0 - Inset;
         HW : constant Float := Wd / 2.0 - Inset;
      begin
         Move (Cr, HL, 0.0);
         Line (Cr, HL - L * 0.22, -HW);
         Line (Cr, -HL, -HW * 0.92);
         Line (Cr, -HL, HW * 0.92);
         Line (Cr, HL - L * 0.22, HW);
         Close_Path (Cr);
      end Hull_Path;
   begin
      Save (Cr);
      Gfx.Translate (Cr, C.X, C.Y);
      Gfx.Rotate (Cr, C.A);
      Color (Cr, 0.0, 0.05, 0.1, 0.3 * Alpha);
      Save (Cr);
      Gfx.Translate (Cr, 0.3, 0.4);
      Hull_Path (0.0);
      Fill (Cr);
      Restore (Cr);
      Color (Cr, Hull, Alpha);
      Hull_Path (0.0);
      Fill_Preserve (Cr);
      Color (Cr, 0.0, 0.0, 0.0, 0.5 * Alpha);
      Width (Cr, 0.08);
      Stroke (Cr);
      case C.Kind is
         when Tourboat =>                --  bateau-mouche: long glass canopy over rows of seats
            Color (Cr, Hex ("#9fb8c8"), 0.85 * Alpha);
            Round_Rect (Cr, -L / 2.0 + 1.5, -Wd / 2.0 + 0.6, L * 0.7, Wd - 1.2, 0.8);
            Fill (Cr);
            Color (Cr, 1.0, 1.0, 1.0, 0.35 * Alpha);
            Width (Cr, 0.06);
            for I in 1 .. 14 loop
               Move (Cr, -L / 2.0 + 1.5 + Float (I) * L * 0.05, -Wd / 2.0 + 0.6);
               Line (Cr, -L / 2.0 + 1.5 + Float (I) * L * 0.05, Wd / 2.0 - 0.6);
            end loop;
            Stroke (Cr);
            Color (Cr, Hex ("#1f3b57"), Alpha);
            Fill_Rect (Cr, L * 0.22, -0.9, 1.4, 1.8);
         when Police_Boat =>
            Color (Cr, Hex ("#1b3d8f"), Alpha);
            Fill_Rect (Cr, -L / 2.0 + 0.3, -Wd / 2.0 + 0.15, L * 0.75, 0.25);
            Fill_Rect (Cr, -L / 2.0 + 0.3, Wd / 2.0 - 0.4, L * 0.75, 0.25);
            Color (Cr, Hex ("#1d2630"), Alpha);
            Fill_Rect (Cr, -0.4, -0.75, 1.4, 1.5);
            declare
               On : constant Boolean := C.Siren and then Blink (6.0);
            begin
               Color (Cr, (if On then Hex ("#3a7bff") else Hex ("#14306a")), Alpha);
               Fill_Rect (Cr, -0.6, -0.5, 0.3, 0.45);
               Color (Cr, (if On then Hex ("#401010") else Hex ("#ff3030")), Alpha);
               Fill_Rect (Cr, -0.6, 0.05, 0.3, 0.45);
            end;
         when others =>                  --  speedboat: windscreen, seats, a stripe
            Color (Cr, (0.96, 0.96, 0.94), Alpha);
            Fill_Rect (Cr, -L / 2.0 + 0.4, -0.1, L * 0.6, 0.2);
            Color (Cr, Hex ("#1d2630"), 0.9 * Alpha);
            Move (Cr, L * 0.12, -Wd / 2.0 + 0.3);
            Line (Cr, L * 0.2, 0.0);
            Line (Cr, L * 0.12, Wd / 2.0 - 0.3);
            Line (Cr, L * 0.05, Wd / 2.0 - 0.3);
            Line (Cr, L * 0.05, -Wd / 2.0 + 0.3);
            Close_Path (Cr);
            Fill (Cr);
            Color (Cr, Hex ("#8b5a2b"), Alpha);
            Fill_Rect (Cr, -L * 0.3, -Wd / 2.0 + 0.35, L * 0.3, Wd - 0.7);
      end case;
      Restore (Cr);
   end Draw_Boat;

   --  helicopter / plane at (X, Y), scaled by S (bigger when high up, closer to the camera)
   procedure Draw_Aircraft (Cr : Cairo_Context; C : Car; X, Y, S : Float; Shadow : Boolean := False) is
      Body_C  : constant RGB := (if C.Dead then Hex ("#262626") else C.Color);
      Running : constant Boolean := (C.Driver /= No_Driver and then not C.Dead) or else C.Z > 0.3;
      Spin    : constant Float := Time * 28.0;
      procedure Col (K : RGB; A : Float := 1.0) is
      begin
         if Shadow then
            Color (Cr, 0.0, 0.0, 0.0, 0.22 * A);
         else
            Color (Cr, K, A);
         end if;
      end Col;
   begin
      Save (Cr);
      Gfx.Translate (Cr, X, Y);
      Gfx.Rotate (Cr, C.A);
      Gfx.Scale (Cr, S);
      if C.Kind = Helicopter then
         Col (Shade (Body_C, -0.15));
         Fill_Rect (Cr, -5.6, -0.25, 4.8, 0.5);                   --  tail boom
         Fill_Rect (Cr, -5.9, -0.9, 0.5, 1.8);                    --  tail fin
         if C.Z < 0.5 and then not Shadow then                     --  skids
            Col (Hex ("#333333"));
            Fill_Rect (Cr, -1.8, -1.35, 3.8, 0.15);
            Fill_Rect (Cr, -1.8, 1.2, 3.8, 0.15);
         end if;
         Col (Body_C);
         Ellipse (Cr, 0.6, 0.0, 2.5, 1.3, 0.0);
         Fill (Cr);
         if not Shadow then
            Col (Hex ("#9fc3d9"), 0.9);
            Ellipse (Cr, 1.9, 0.0, 1.0, 0.95, 0.0);
            Fill (Cr);
         end if;
         --  main rotor: a blur disc and two blades
         if Running then
            Col ((0.1, 0.1, 0.1), 0.18);
            Fill_Circle (Cr, 0.4, 0.0, 5.3);
         end if;
         Col (Hex ("#222222"), (if Running then 0.6 else 1.0));
         Width (Cr, 0.28);
         declare
            A : constant Float := (if Running then Spin else 0.5);
         begin
            Move (Cr, 0.4 - Cos (A) * 5.3, -Sin (A) * 5.3); Line (Cr, 0.4 + Cos (A) * 5.3, Sin (A) * 5.3);
            Move (Cr, 0.4 + Sin (A) * 5.3, -Cos (A) * 5.3); Line (Cr, 0.4 - Sin (A) * 5.3, Cos (A) * 5.3);
         end;
         Stroke (Cr);
         Fill_Circle (Cr, 0.4, 0.0, 0.3);
      else
         --  plane: wings, tailplane, fuselage, propeller
         Col (Shade (Body_C, -0.05));
         Move (Cr, 1.2, -5.3); Line (Cr, 1.9, -5.3); Line (Cr, 1.4, 5.3); Line (Cr, 0.6, 5.3);
         Close_Path (Cr);
         Move (Cr, 1.2, -5.3); Line (Cr, -0.4, -5.1); Line (Cr, -0.4, 5.1); Line (Cr, 0.6, 5.3);
         Close_Path (Cr);
         Fill (Cr);
         Move (Cr, -3.3, -1.8); Line (Cr, -2.9, -1.8); Line (Cr, -2.9, 1.8); Line (Cr, -3.5, 1.8);
         Line (Cr, -4.2, 1.8); Line (Cr, -4.2, -1.8);
         Close_Path (Cr);
         Fill (Cr);
         Col (Body_C);
         Ellipse (Cr, 0.0, 0.0, 4.5, 0.62, 0.0);
         Fill (Cr);
         if not Shadow then
            Col (Hex ("#c0392b"));
            Fill_Rect (Cr, -4.0, -0.12, 7.0, 0.24);
            Fill_Rect (Cr, 0.9, -5.2, 0.5, 0.6);
            Fill_Rect (Cr, 0.5, 4.6, 0.5, 0.6);
            Col (Hex ("#2c3e50"), 0.9);
            Ellipse (Cr, 1.9, 0.0, 0.8, 0.42, 0.0);
            Fill (Cr);
         end if;
         Col (Hex ("#222222"), (if Running then 0.35 else 1.0));
         if Running then
            Fill_Circle (Cr, 4.6, 0.0, 1.1);
         else
            Fill_Rect (Cr, 4.5, -1.1, 0.12, 2.2);
         end if;
      end if;
      Restore (Cr);
   end Draw_Aircraft;

   procedure Draw_Car (Cr : Cairo_Context; C : Car) is
      P    : Car_Params renames Params (C.Kind);
      L    : constant Float := P.Len;
      Wd   : constant Float := P.Wid;
      Body_C : constant RGB := (if C.Dead then Hex ("#262626") else C.Color);
      Glass  : constant RGB := Hex ("#1d2630");
      Alpha  : constant Float := (if C.Sunk then Float'Max (0.0, 1.0 - C.Sink_T / 3.0) else 1.0);
   begin
      if Is_Air (C.Kind) then           --  in the air: only its shadow is down here
         if C.Z > 0.5 then
            Draw_Aircraft (Cr, C, C.X + C.Z * 0.3, C.Y + C.Z * 0.4, 1.0, Shadow => True);
         else
            Draw_Aircraft (Cr, C, C.X, C.Y, 1.0);
         end if;
         return;
      end if;
      if Is_Boat (C.Kind) then
         Draw_Boat (Cr, C, Alpha);
         return;
      end if;
      Save (Cr);
      Gfx.Translate (Cr, C.X, C.Y);
      Gfx.Rotate (Cr, C.A);
      Color (Cr, 0.0, 0.0, 0.0, 0.35 * Alpha);
      Round_Rect (Cr, -L / 2.0 + 0.25, -Wd / 2.0 + 0.35, L, Wd, 0.5);
      Fill (Cr);
      Color (Cr, Body_C, Alpha);
      Round_Rect (Cr, -L / 2.0, -Wd / 2.0, L, Wd, (if C.Kind = Bus then 0.35 else 0.5));
      Fill_Preserve (Cr);
      Color (Cr, 0.0, 0.0, 0.0, 0.5 * Alpha);
      Width (Cr, 0.08);
      Stroke (Cr);
      case C.Kind is
         when Bus =>
            Color (Cr, (if C.Dead then Hex ("#222222") else Hex ("#eef0ea")), Alpha);
            Fill_Rect (Cr, -L / 2.0 + 0.4, -Wd / 2.0 + 0.25, L - 0.8, Wd - 0.5);
            Color (Cr, Glass, Alpha);
            Fill_Rect (Cr, L / 2.0 - 0.55, -Wd / 2.0 + 0.2, 0.4, Wd - 0.4);
            Color (Cr, 0.0, 0.0, 0.0, 0.25 * Alpha);
            for I in 0 .. 3 loop
               Fill_Rect (Cr, -L / 2.0 + 1.5 + Float (I) * 2.3, -0.5, 1.2, 1.0);
            end loop;
         when Van =>
            Color (Cr, Glass, Alpha);
            Fill_Rect (Cr, L / 2.0 - 1.25, -Wd / 2.0 + 0.18, 0.45, Wd - 0.36);
            Color (Cr, Shade (Body_C, -0.08), Alpha);
            Fill_Rect (Cr, -L / 2.0 + 0.15, -Wd / 2.0 + 0.12, L - 1.6, Wd - 0.24);
            Color (Cr, 0.0, 0.0, 0.0, 0.2 * Alpha);
            Width (Cr, 0.05);
            for I in 1 .. 5 loop
               Move (Cr, -L / 2.0 + 0.15 + Float (I) * 0.6, -Wd / 2.0 + 0.2);
               Line (Cr, -L / 2.0 + 0.15 + Float (I) * 0.6, Wd / 2.0 - 0.2);
            end loop;
            Stroke (Cr);
         when Scooter =>                 --  seat, handlebar, and a helmeted rider when driven
            Color (Cr, Hex ("#222222"), Alpha);
            Fill_Rect (Cr, -L * 0.3, -0.18, L * 0.45, 0.36);
            Width (Cr, 0.08);
            Move (Cr, L * 0.3, -0.42); Line (Cr, L * 0.3, 0.42);
            Stroke (Cr);
            if C.Driver /= No_Driver and then not C.Dead then
               Color (Cr, Hex ("#2c3e50"), Alpha);
               Ellipse (Cr, -L * 0.05, 0.0, 0.32, 0.3, 0.0);
               Fill (Cr);
               Color (Cr, (if C.Driver = Player_Driver then Hex ("#f1c40f") else Shade (C.Color, -0.3)), Alpha);
               Fill_Circle (Cr, L * 0.02, 0.0, 0.2);
            end if;
         when Tank =>                    --  tracks, hull, turret and gun
            declare
               Tread : constant Float := (Time * Physics.Fwd_Speed (C) * 2.0) - Float'Floor (Time * Physics.Fwd_Speed (C) * 2.0);
               Rel   : constant Float := C.Turret - C.A;
            begin
               Color (Cr, Hex ("#2b2b26"), Alpha);
               Fill_Rect (Cr, -L / 2.0, -Wd / 2.0, L, 0.75);
               Fill_Rect (Cr, -L / 2.0, Wd / 2.0 - 0.75, L, 0.75);
               Color (Cr, Hex ("#55554a"), Alpha);
               Width (Cr, 0.12);
               for I in 0 .. 13 loop
                  declare
                     TX : constant Float := -L / 2.0 + (Float (I) + Tread) * L / 14.0;
                  begin
                     Move (Cr, TX, -Wd / 2.0); Line (Cr, TX, -Wd / 2.0 + 0.75);
                     Move (Cr, TX, Wd / 2.0 - 0.75); Line (Cr, TX, Wd / 2.0);
                  end;
               end loop;
               Stroke (Cr);
               Color (Cr, Shade (Body_C, -0.12), Alpha);
               Fill_Rect (Cr, -L / 2.0 + 0.4, -Wd / 2.0 + 0.8, L - 0.8, Wd - 1.6);
               Save (Cr);
               Gfx.Rotate (Cr, Rel);
               Color (Cr, Hex ("#2f3418"), Alpha);
               Fill_Rect (Cr, 0.5, -0.17, 3.9, 0.34);
               Color (Cr, Shade (Body_C, 0.08), Alpha);
               Round_Rect (Cr, -1.4, -1.15, 2.6, 2.3, 0.7);
               Fill_Preserve (Cr);
               Color (Cr, 0.0, 0.0, 0.0, 0.4 * Alpha);
               Width (Cr, 0.08);
               Stroke (Cr);
               Color (Cr, Shade (Body_C, -0.2), Alpha);
               Fill_Circle (Cr, -0.35, 0.35, 0.38);
               Restore (Cr);
            end;
         when Escargot =>                --  round little car with a rolled canvas roof
            Color (Cr, Glass, Alpha);
            Fill_Rect (Cr, L * 0.12, -Wd / 2.0 + 0.2, L * 0.16, Wd - 0.4);
            Color (Cr, Hex ("#4a4f46"), Alpha);
            Round_Rect (Cr, -L * 0.3, -Wd / 2.0 + 0.22, L * 0.42, Wd - 0.44, 0.3);
            Fill (Cr);
            Color (Cr, 0.0, 0.0, 0.0, 0.25 * Alpha);
            Width (Cr, 0.05);
            for I in 1 .. 4 loop
               Move (Cr, -L * 0.3 + Float (I) * L * 0.084, -Wd / 2.0 + 0.25);
               Line (Cr, -L * 0.3 + Float (I) * L * 0.084, Wd / 2.0 - 0.25);
            end loop;
            Stroke (Cr);
            Color (Cr, Shade (Body_C, -0.2), Alpha);       --  round mudguards
            for SX in -1 .. 1 loop
               if SX /= 0 then
                  Fill_Circle (Cr, Float (SX) * L * 0.33, -Wd / 2.0 + 0.05, 0.32);
                  Fill_Circle (Cr, Float (SX) * L * 0.33, Wd / 2.0 - 0.05, 0.32);
               end if;
            end loop;
         when Fournil =>                 --  bakery van: baguettes painted on the roof
            Color (Cr, Glass, Alpha);
            Fill_Rect (Cr, L / 2.0 - 1.25, -Wd / 2.0 + 0.18, 0.45, Wd - 0.36);
            Color (Cr, Hex ("#f3e3c0"), Alpha);
            Fill_Rect (Cr, -L / 2.0 + 0.15, -Wd / 2.0 + 0.12, L - 1.6, Wd - 0.24);
            for I in 0 .. 2 loop
               Color (Cr, Hex ("#c58a3d"), Alpha);
               Ellipse (Cr, -L / 2.0 + 1.75, -0.55 + Float (I) * 0.55, 1.3, 0.16, 0.08 * Float (I - 1));
               Fill (Cr);
               Color (Cr, Hex ("#8a5a22"), Alpha);
               Width (Cr, 0.04);
               for J in -1 .. 1 loop
                  Move (Cr, -L / 2.0 + 1.75 + Float (J) * 0.5 - 0.12, -0.55 + Float (I) * 0.55 - 0.08);
                  Line (Cr, -L / 2.0 + 1.75 + Float (J) * 0.5 + 0.12, -0.55 + Float (I) * 0.55 + 0.08);
               end loop;
               Stroke (Cr);
            end loop;
         when Fusee =>                   --  rocket car: long nose, fins, twin exhausts
            Color (Cr, Glass, Alpha);
            Move (Cr, L * 0.05, -Wd / 2.0 + 0.3); Line (Cr, L * 0.22, -0.2); Line (Cr, L * 0.22, 0.2);
            Line (Cr, L * 0.05, Wd / 2.0 - 0.3); Close_Path (Cr);
            Fill (Cr);
            Color (Cr, Hex ("#ffd23a"), Alpha);
            Fill_Rect (Cr, -L / 2.0 + 0.1, -0.12, L * 0.85, 0.24);
            Color (Cr, Hex ("#2a2a2a"), Alpha);
            Move (Cr, -L / 2.0, -Wd / 2.0 - 0.25); Line (Cr, -L / 2.0 + 0.9, -Wd / 2.0); Line (Cr, -L / 2.0, -Wd / 2.0 + 0.3);
            Close_Path (Cr);
            Move (Cr, -L / 2.0, Wd / 2.0 + 0.25); Line (Cr, -L / 2.0 + 0.9, Wd / 2.0); Line (Cr, -L / 2.0, Wd / 2.0 - 0.3);
            Close_Path (Cr);
            Fill (Cr);
            Color (Cr, Hex ("#555555"), Alpha);
            Fill_Circle (Cr, -L / 2.0 + 0.05, -0.45, 0.18);
            Fill_Circle (Cr, -L / 2.0 + 0.05, 0.45, 0.18);
         when others =>
            Color (Cr, Glass, Alpha);
            Move (Cr, L * 0.3, -Wd / 2.0 + 0.12);
            Line (Cr, L * 0.3, Wd / 2.0 - 0.12);
            Line (Cr, L * 0.1, Wd / 2.0 - 0.2);
            Line (Cr, L * 0.1, -Wd / 2.0 + 0.2);
            Close_Path (Cr);
            Fill (Cr);
            Fill_Rect (Cr, -L * 0.36, -Wd / 2.0 + 0.22, L * 0.1, Wd - 0.44);
            Color (Cr, (if C.Dead then Hex ("#1e1e1e")
                        else Shade (C.Color, (if C.Kind = Police then -0.05 else 0.18))), Alpha);
            Fill_Rect (Cr, -L * 0.26, -Wd / 2.0 + 0.2, L * 0.36, Wd - 0.4);
            if C.Kind = Sport then
               Color (Cr, 0.0, 0.0, 0.0, 0.6 * Alpha);
               Fill_Rect (Cr, -L / 2.0 + 0.1, -0.15, L * 0.55, 0.3);
            end if;
            if C.Kind = Police and then not C.Dead then
               Color (Cr, Hex ("#1b3d8f"), Alpha);
               Fill_Rect (Cr, -L / 2.0 + 0.1, -Wd / 2.0, L - 0.2, 0.2);
               Fill_Rect (Cr, -L / 2.0 + 0.1, Wd / 2.0 - 0.2, L - 0.2, 0.2);
               Fill_Rect (Cr, L / 2.0 - 0.6, -Wd / 2.0 + 0.2, 0.45, Wd - 0.4);
               declare
                  On : constant Boolean := C.Siren and then Blink (6.0);
               begin
                  Color (Cr, (if On then Hex ("#3a7bff") else Hex ("#14306a")), Alpha);
                  Fill_Rect (Cr, -0.15, -0.65, 0.35, 0.6);
                  Color (Cr, (if On then Hex ("#401010") else Hex ("#ff3030")), Alpha);
                  Fill_Rect (Cr, -0.15, 0.05, 0.35, 0.6);
               end;
            end if;
            if C.Kind = Taxi and then not C.Dead then
               Color (Cr, Hex ("#e8e8e0"), Alpha);
               Fill_Rect (Cr, -0.25, -0.35, 0.4, 0.7);
               Color (Cr, Hex ("#3cff6a"), Alpha);
               Fill_Rect (Cr, -0.2, -0.3, 0.3, 0.12);
            end if;
      end case;
      if not C.Dead then
         Color (Cr, Hex ("#fff6c8"), Alpha);
         Fill_Rect (Cr, L / 2.0 - 0.15, -Wd / 2.0 + 0.15, 0.15, 0.35);
         Fill_Rect (Cr, L / 2.0 - 0.15, Wd / 2.0 - 0.5, 0.15, 0.35);
         declare
            Braking : constant Boolean := C.Throttle < 0.0 and then Physics.Fwd_Speed (C) > 0.5
              and then C.Driver /= No_Driver;
         begin
            Color (Cr, (if Braking then Hex ("#ff2020") else Hex ("#8a1010")), Alpha);
         end;
         Fill_Rect (Cr, -L / 2.0, -Wd / 2.0 + 0.15, 0.13, 0.35);
         Fill_Rect (Cr, -L / 2.0, Wd / 2.0 - 0.5, 0.13, 0.35);
         if C.HP < P.HP * 0.5 then
            Color (Cr, 0.08, 0.08, 0.08, 0.35 * Alpha);
            Circle (Cr, L * 0.3, Wd * 0.2, 0.5);
            Circle (Cr, -L * 0.2, -Wd * 0.25, 0.4);
            Fill (Cr);
         end if;
      end if;
      Restore (Cr);
   end Draw_Car;

   ------------------------------------------------------------------ peds
   procedure Draw_Ped (Cr : Cairo_Context; P : Ped) is
   begin
      Save (Cr);
      Gfx.Translate (Cr, P.X, P.Y);
      Gfx.Rotate (Cr, P.A);
      if P.Dead then
         Color (Cr, P.Shirt);
         Ellipse (Cr, 0.0, 0.0, 0.5, 0.25, 0.4);
         Fill (Cr);
         Color (Cr, P.Hair);
         Fill_Circle (Cr, 0.5, 0.2, 0.17);
         Color (Cr, P.Skin);
         Fill_Rect (Cr, -0.1, -0.55, 0.12, 0.35);
         Fill_Rect (Cr, 0.1, 0.25, 0.12, 0.35);
         Restore (Cr);
         return;
      end if;
      Gfx.Scale (Cr, 1.9);
      declare
         SW : constant Float := (if P.Moving then Sin (P.Phase) * 0.2 else 0.0);
      begin
         Color (Cr, 0.0, 0.0, 0.0, 0.3);
         Ellipse (Cr, 0.06, 0.08, 0.24, 0.32, 0.0);
         Fill (Cr);
         Color (Cr, Hex ("#222222"));
         Fill_Rect (Cr, SW - 0.08, -0.15, 0.18, 0.11);
         Fill_Rect (Cr, -SW - 0.08, 0.04, 0.18, 0.11);
         Color (Cr, P.Skin);
         Circle (Cr, -SW * 0.8, -0.27, 0.07);
         Circle (Cr, SW * 0.8, 0.27, 0.07);
         Fill (Cr);
         if P.Armed or else (P.Is_Player and then Weapon > 0) then
            Color (Cr, Hex ("#111111"));
            Fill_Rect (Cr, 0.1, 0.12, 0.32, 0.07);
         end if;
         Color (Cr, P.Shirt);
         Ellipse (Cr, 0.0, 0.0, 0.15, 0.26, 0.0);
         Fill (Cr);
         if P.Cop then
            Color (Cr, Hex ("#c8a62a"));
            Fill_Rect (Cr, 0.02, -0.04, 0.06, 0.08);
         end if;
         Color (Cr, P.Hair);
         Fill_Circle (Cr, 0.01, 0.0, 0.13);
         if P.Cop then
            Color (Cr, Hex ("#0b1530"));
            Fill_Rect (Cr, 0.05, -0.12, 0.1, 0.24);
         end if;
         case P.Role is
            when Mime =>         --  striped shirt, black beret, hands on an invisible wall
               Color (Cr, Hex ("#111111"));
               for I in -1 .. 1 loop
                  Fill_Rect (Cr, -0.13, Float (I) * 0.09 - 0.02, 0.26, 0.04);
               end loop;
               Fill_Circle (Cr, -0.02, 0.0, 0.1);
               declare
                  Push : constant Float := 0.36 + Sin (P.Phase) * 0.06;
               begin
                  Color (Cr, (0.97, 0.97, 0.97));
                  Fill_Circle (Cr, Push, -0.18 + Sin (P.Phase * 0.7) * 0.08, 0.06);
                  Fill_Circle (Cr, Push, 0.18 - Sin (P.Phase * 0.7) * 0.08, 0.06);
               end;
            when Musician =>     --  an accordion, squeezing in and out
               declare
                  Sq : constant Float := 0.16 + Sin (P.Phase * 2.2) * 0.07;
               begin
                  Color (Cr, Hex ("#2b2b2b"));
                  Fill_Rect (Cr, 0.14, -Sq - 0.05, 0.14, 0.1);
                  Fill_Rect (Cr, 0.14, Sq - 0.05, 0.14, 0.1);
                  Color (Cr, Hex ("#c0392b"));
                  Fill_Rect (Cr, 0.16, -Sq + 0.05, 0.1, 2.0 * Sq - 0.1);
                  Color (Cr, 0.0, 0.0, 0.0, 0.5);
                  Width (Cr, 0.015);
                  for I in 1 .. 4 loop
                     Move (Cr, 0.16, -Sq + 0.05 + Float (I) * (2.0 * Sq - 0.1) / 5.0);
                     Line (Cr, 0.26, -Sq + 0.05 + Float (I) * (2.0 * Sq - 0.1) / 5.0);
                  end loop;
                  Stroke (Cr);
               end;
            when Marcher =>      --  every other marcher carries a placard
               if P.Serial mod 2 = 0 then
                  Color (Cr, Hex ("#6b4a2b"));
                  Fill_Rect (Cr, 0.0, -0.02, 0.35, 0.04);
                  Color (Cr, (0.96, 0.95, 0.9));
                  Fill_Rect (Cr, 0.3, -0.28, 0.12, 0.56);
                  Color (Cr, (if P.Serial mod 3 = 0 then Hex ("#c62828") else Hex ("#1a1a1a")));
                  Fill_Rect (Cr, 0.33, -0.2, 0.05, 0.4);
               end if;
            when Citizen =>
               null;
         end case;
      end;
      Restore (Cr);
   end Draw_Ped;

   ------------------------------------------------------------------ effects
   procedure Draw_Particle (Cr : Cairo_Context; Q : Particle) is
      F : constant Float := Q.Life / Q.Max;
   begin
      case Q.Kind is
         when Smoke =>
            Color (Cr, 0.24, 0.24, 0.24, 0.35 * F); Fill_Circle (Cr, Q.X, Q.Y, Q.S * (2.0 - F));
         when Fire =>
            Color (Cr, 1.0, (120.0 + 120.0 * F) / 255.0, 0.12, 0.8 * F); Fill_Circle (Cr, Q.X, Q.Y, Q.S * (0.5 + F));
         when Boom =>
            Color (Cr, 1.0, 0.7 * F, 0.24 * F, 0.9 * F); Fill_Circle (Cr, Q.X, Q.Y, Q.S * (1.6 - F * 0.6));
         when Spark =>
            Color (Cr, 1.0, 0.9, 0.47, F); Fill_Rect (Cr, Q.X, Q.Y, 0.15, 0.15);
         when Blood_Drop =>
            Color (Cr, 0.59, 0.04, 0.04, F); Fill_Circle (Cr, Q.X, Q.Y, Q.S);
         when Debris =>
            Color (Cr, 0.16, 0.16, 0.16, F); Fill_Rect (Cr, Q.X, Q.Y, Q.S, Q.S);
         when Flash =>
            Color (Cr, 1.0, 0.9, 0.47, 0.9); Fill_Circle (Cr, Q.X, Q.Y, 0.4);
         when Splash =>
            Color (Cr, 0.86, 0.94, 1.0, F); Width (Cr, 0.1);
            New_Path (Cr); Circle (Cr, Q.X, Q.Y, Q.S * (2.0 - F)); Stroke (Cr);
      end case;
   end Draw_Particle;

   procedure Draw_Pickup (Cr : Cairo_Context; K : Pickup) is
      B : constant Float := Sin (Time * 4.0 + K.X) * 0.1;
      C : RGB;
      Letter : String (1 .. 1);
   begin
      case K.Kind is
         when Cash         => C := Hex ("#2ecc71"); Letter := "$";
         when Pistol_Ammo  => C := Hex ("#bdc3c7"); Letter := "P";
         when SMG_Ammo     => C := Hex ("#e67e22"); Letter := "S";
         when Health       => C := Hex ("#ffffff"); Letter := "+";
         when Body_Armor   => C := Hex ("#3498db"); Letter := "A";
         when Shotgun_Ammo => C := Hex ("#c0392b"); Letter := "F";   --  fusil
         when Grenade_Box  => C := Hex ("#6b8e23"); Letter := "G";
         when Rocket_Ammo  => C := Hex ("#f1c40f"); Letter := "R";
      end case;
      Save (Cr);
      Gfx.Translate (Cr, K.X, K.Y);
      Color (Cr, 0.0, 0.0, 0.0, 0.3);
      Ellipse (Cr, 0.1, 0.15, 0.55, 0.4, 0.0);
      Fill (Cr);
      Gfx.Scale (Cr, 1.0 + B);
      Color (Cr, C);
      Round_Rect (Cr, -0.55, -0.55, 1.1, 1.1, 0.2);
      Fill_Preserve (Cr);
      Color (Cr, 0.07, 0.07, 0.07);
      Width (Cr, 0.08);
      Stroke (Cr);
      if K.Kind = Health then
         Color (Cr, Hex ("#e02020"));
         Fill_Rect (Cr, -0.12, -0.38, 0.24, 0.76);
         Fill_Rect (Cr, -0.38, -0.12, 0.76, 0.24);
      else
         Text (Cr, Letter, 0.0, -0.36, 0.7, (0.07, 0.07, 0.07), Center, Outline => 0.0);
      end if;
      Restore (Cr);
   end Draw_Pickup;

   procedure Draw_Phone_Icon (Cr : Cairo_Context; X, Y, S : Float) is
   begin
      --  a small handset: two ear/mouth pieces joined by a bar
      Width (Cr, S * 0.22);
      Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
      Move (Cr, X - S * 0.32, Y + S * 0.12);
      Line (Cr, X - S * 0.2, Y - S * 0.12);
      Line (Cr, X + S * 0.2, Y - S * 0.12);
      Line (Cr, X + S * 0.32, Y + S * 0.12);
      Stroke (Cr);
      Fill_Rect (Cr, X - S * 0.25, Y + S * 0.02, S * 0.5, S * 0.25);
   end Draw_Phone_Icon;

   procedure Draw_Markers (Cr : Cairo_Context) is
      Pulse : constant Float := 1.0 + Sin (Time * 5.0) * 0.15;
   begin
      if not Has_Mission then
         for Ph of Phones loop
            if Ph.On and then Ph.Cool <= 0.0 then
               declare
                  S : Spot renames Spots (Ph.S);
               begin
                  Color (Cr, 0.31, 1.0, 0.47, 0.9);
                  Width (Cr, 0.25);
                  New_Path (Cr);
                  Circle (Cr, S.PX, S.PY, 1.8 * Pulse);
                  Stroke (Cr);
                  Color (Cr, Hex ("#1e8f3a"));
                  Round_Rect (Cr, S.PX - 0.6, S.PY - 0.6, 1.2, 1.2, 0.2);
                  Fill (Cr);
                  Color (Cr, White);
                  Draw_Phone_Icon (Cr, S.PX, S.PY, 0.9);
               end;
            end if;
         end loop;
      elsif Mis.Has_Target_Pos then
         Color (Cr, 1.0, 0.82, 0.24, 0.95);
         Width (Cr, 0.35);
         New_Path (Cr);
         Circle (Cr, Mis.TX, Mis.TY,
                 (if Mis.Kind = Hit_Job or else (Mis.Kind = Steal and then Mis.Stage = 0) then 2.5 else 7.0) * Pulse);
         Stroke (Cr);
      end if;
   end Draw_Markers;

   ------------------------------------------------------------------ world
   procedure Draw_World (Cr : Cairo_Context) is
      SX : constant Float := (if Shake > 0.0 then Rand (-1.0, 1.0) * Shake * 0.8 else 0.0);
      SY : constant Float := (if Shake > 0.0 then Rand (-1.0, 1.0) * Shake * 0.8 else 0.0);
      CX : constant Float := Cam_X + SX;
      CY : constant Float := Cam_Y + SY;
   begin
      Save (Cr);
      Gfx.Translate (Cr, Screen_W / 2.0, Screen_H / 2.0);
      Gfx.Scale (Cr, Cam_Z);
      Gfx.Translate (Cr, -CX, -CY);
      World_Render.Draw_Ground (Cr, View_X0, View_Y0, View_X1, View_Y1, (if Mode = Title then 99 else 4));
      Secrets.Draw_Ground (Cr);
      --  decals
      Color (Cr, 0.08, 0.08, 0.08, 0.45);
      for I in 0 .. Scorch_Count - 1 loop
         Fill_Circle (Cr, Scorch (I).X, Scorch (I).Y, Scorch (I).R);
      end loop;
      Color (Cr, 0.06, 0.06, 0.06, 0.4);
      Width (Cr, 0.22);
      New_Path (Cr);
      for I in 0 .. Skid_Count - 1 loop
         declare
            S : Seg renames Skids (I);
         begin
            if Game.On_Screen (S.X0, S.Y0, 5.0) then
               Move (Cr, S.X0, S.Y0);
               Line (Cr, S.X1, S.Y1);
            end if;
         end;
      end loop;
      Stroke (Cr);
      Color (Cr, 0.47, 0.03, 0.03, 0.75);
      for I in 0 .. Blood_Count - 1 loop
         if Game.On_Screen (Blood (I).X, Blood (I).Y) then
            Ellipse (Cr, Blood (I).X, Blood (I).Y, Blood (I).R, Blood (I).R * 0.7, Blood (I).A);
            Fill (Cr);
         end if;
      end loop;
      Draw_Markers (Cr);
      for K of Pickups loop
         if K.Active and then Game.On_Screen (K.X, K.Y) then
            Draw_Pickup (Cr, K);
         end if;
      end loop;
      for P of Peds loop
         if P.Active and then P.Dead and then Game.On_Screen (P.X, P.Y) then
            Draw_Ped (Cr, P);
         end if;
      end loop;
      for P of Peds loop
         if P.Active and then not P.Dead and then not (P.Is_Player and then Player_Car /= 0)
           and then Game.On_Screen (P.X, P.Y)
         then
            Draw_Ped (Cr, P);
         end if;
      end loop;
      --  boats first, then the bridge decks above them, then everything on the road
      for C of Cars loop
         if C.Active and then Is_Boat (C.Kind) and then Game.On_Screen (C.X, C.Y, Params (C.Kind).Len) then
            Draw_Car (Cr, C);
            declare
               R : constant Float := Params (C.Kind).Len;
            begin
               World_Render.Draw_Bridges (Cr, C.X - R, C.Y - R, C.X + R, C.Y + R);
            end;
         end if;
      end loop;
      for C of Cars loop
         if C.Active and then not Is_Boat (C.Kind) and then Game.On_Screen (C.X, C.Y, Params (C.Kind).Len) then
            Draw_Car (Cr, C);
         end if;
      end loop;
      for Q of Projs loop
         if Q.Active and then Game.On_Screen (Q.X, Q.Y) then
            Color (Cr, 0.0, 0.0, 0.0, 0.3);
            Fill_Circle (Cr, Q.X + 0.15, Q.Y + 0.2, 0.18);
            case Q.Kind is
               when Grenade =>
                  Color (Cr, Hex ("#3d4a1e"));
                  Fill_Circle (Cr, Q.X - Q.Z * 0.15, Q.Y - Q.Z * 0.3, 0.17 + Q.Z * 0.02);
                  if Blink (8.0) then
                     Color (Cr, Hex ("#ff4030"));
                     Fill_Circle (Cr, Q.X - Q.Z * 0.15, Q.Y - Q.Z * 0.3, 0.06);
                  end if;
               when Rocket | Shell =>
                  declare
                     A : constant Float := Arctan (Q.VY, Q.VX);
                     L : constant Float := (if Q.Kind = Rocket then 0.7 else 0.4);
                  begin
                     Color (Cr, 1.0, 0.75, 0.2, 0.9);
                     Fill_Circle (Cr, Q.X - Cos (A) * L, Q.Y - Sin (A) * L, 0.22);
                     Color (Cr, (if Q.Kind = Rocket then Hex ("#5d6d4a") else Hex ("#c9b458")));
                     Width (Cr, (if Q.Kind = Rocket then 0.22 else 0.16));
                     Move (Cr, Q.X - Cos (A) * L, Q.Y - Sin (A) * L);
                     Line (Cr, Q.X + Cos (A) * L * 0.5, Q.Y + Sin (A) * L * 0.5);
                     Stroke (Cr);
                  end;
            end case;
         end if;
      end loop;
      for Q of Parts loop
         if Q.Active and then not Q.Top then
            Draw_Particle (Cr, Q);
         end if;
      end loop;
      Width (Cr, 0.08);
      Color (Cr, 1.0, 0.94, 0.59, 0.9);
      for T of Tracers loop
         if T.Life > 0.0 then
            Move (Cr, T.X0, T.Y0);
            Line (Cr, T.X1, T.Y1);
            Stroke (Cr);
         end if;
      end loop;
      World_Render.Draw_Buildings (Cr, CX, CY, View_W * 1.35, View_X0, View_Y0, View_X1, View_Y1,
                                    Cam_Z);
      Secrets.Draw_Air (Cr, CX, CY, View_W * 1.35);
      for C of Cars loop                --  aircraft above the rooftops, in perspective
         if C.Active and then Is_Air (C.Kind) and then C.Z > 0.5 then
            declare
               K : constant Float := C.Z / Float'Max (View_W * 1.35 - C.Z, 20.0);
            begin
               Draw_Aircraft (Cr, C, C.X + (C.X - CX) * K, C.Y + (C.Y - CY) * K, 1.0 + K);
            end;
         end if;
      end loop;
      for Q of Parts loop
         if Q.Active and then Q.Top then
            Draw_Particle (Cr, Q);
         end if;
      end loop;
      for C of Cars loop
         if C.Active and then C.Siren and then not C.Dead and then Game.On_Screen (C.X, C.Y) then
            if Blink (6.0) then
               Color (Cr, 0.24, 0.47, 1.0, 0.18);
            else
               Color (Cr, 1.0, 0.16, 0.16, 0.18);
            end if;
            Fill_Circle (Cr, C.X, C.Y, 5.0);
         end if;
      end loop;
      Restore (Cr);
   end Draw_World;

   ------------------------------------------------------------------ HUD
   procedure Star (Cr : Cairo_Context; X, Y, R : Float; Filled : Boolean; C : RGB) is
   begin
      New_Path (Cr);
      for I in 0 .. 9 loop
         declare
            A  : constant Float := -Pi / 2.0 + Float (I) * Pi / 5.0;
            RR : constant Float := (if I mod 2 = 0 then R else R * 0.45);
         begin
            if I = 0 then
               Move (Cr, X + Cos (A) * RR, Y + Sin (A) * RR);
            else
               Line (Cr, X + Cos (A) * RR, Y + Sin (A) * RR);
            end if;
         end;
      end loop;
      Close_Path (Cr);
      Color (Cr, 0.0, 0.0, 0.0, 0.85);
      Width (Cr, 3.0);
      Stroke_Preserve (Cr);
      if Filled then
         Color (Cr, C);
         Fill (Cr);
      else
         Color (Cr, C);
         Width (Cr, 1.2);
         Stroke (Cr);
      end if;
   end Star;

   procedure Draw_Minimap (Cr : Cairo_Context; S : Float; Has_T : Boolean; TX, TY : Float; T_Phone : Boolean) is
      PL    : Ped renames Peds (Player);
      Size  : constant Float := 190.0 * S;
      X0    : constant Float := 18.0 * S;
      Y0    : constant Float := Screen_H - Size - 18.0 * S;
      Rng   : constant Float := 420.0;
      K     : constant Float := Size / Rng;
      MS    : constant Float := World_Render.Minimap_Scale;
      function MX (X : Float) return Float is (X0 + (X - PL.X + Rng / 2.0) * K);
      function MY (Y : Float) return Float is (Y0 + (Y - PL.Y + Rng / 2.0) * K);
   begin
      Save (Cr);
      Rect (Cr, X0, Y0, Size, Size);
      Clip (Cr);
      Color (Cr, Hex ("#2b3a44"));
      Paint (Cr);
      Save (Cr);
      Gfx.Translate (Cr, X0, Y0);
      Gfx.Scale (Cr, K / MS);
      Set_Source_Surface (Cr, World_Render.Minimap,
                          Glib.Gdouble (-(PL.X - Rng / 2.0) * MS), Glib.Gdouble (-(PL.Y - Rng / 2.0) * MS));
      Paint (Cr);
      Restore (Cr);
      for C of Cars loop
         if C.Active and then C.Kind = Police and then not C.Dead and then C.Driver /= No_Driver then
            Color (Cr, (if Blink (6.0) then Hex ("#3a7bff") else Hex ("#ff3030")));
            Fill_Rect (Cr, MX (C.X) - 3.0, MY (C.Y) - 3.0, 6.0, 6.0);
         end if;
      end loop;
      if not Has_Mission then
         for Ph of Phones loop
            if Ph.On and then Ph.Cool <= 0.0 then
               Color (Cr, Phone_G);
               Fill_Circle (Cr, MX (Spots (Ph.S).PX), MY (Spots (Ph.S).PY), 4.5);
            end if;
         end loop;
      end if;
      if Has_T then
         Color (Cr, (if T_Phone then Phone_G else Yellow));
         New_Path (Cr);
         Circle (Cr, Clamp (MX (TX), X0 + 5.0, X0 + Size - 5.0), Clamp (MY (TY), Y0 + 5.0, Y0 + Size - 5.0), 5.5);
         Fill_Preserve (Cr);
         Color (Cr, 0.0, 0.0, 0.0);
         Width (Cr, 1.5);
         Stroke (Cr);
      end if;
      Gfx.Translate (Cr, MX (PL.X), MY (PL.Y));
      Gfx.Rotate (Cr, (if Player_Car /= 0 then Cars (Player_Car).A else PL.A));
      Move (Cr, 8.0, 0.0); Line (Cr, -5.0, -5.0); Line (Cr, -5.0, 5.0); Close_Path (Cr);
      Color (Cr, White);
      Fill_Preserve (Cr);
      Color (Cr, 0.0, 0.0, 0.0);
      Width (Cr, 1.5);
      Stroke (Cr);
      Restore (Cr);
      Color (Cr, 0.0, 0.0, 0.0, 0.8);
      Width (Cr, 3.0);
      Rect (Cr, X0, Y0, Size, Size);
      Stroke (Cr);
      Color (Cr, 1.0, 1.0, 1.0, 0.5);
      Width (Cr, 1.0);
      Rect (Cr, X0, Y0, Size, Size);
      Stroke (Cr);
   end Draw_Minimap;

   procedure Draw_HUD (Cr : Cairo_Context) is
      PL : Ped renames Peds (Player);
      W  : constant Float := Screen_W;
      H  : constant Float := Screen_H;
      S  : constant Float := Float'Max (0.75, Float'Min (1.3, W / 1400.0));
      Has_T, T_Phone : Boolean;
      TX, TY : Float;
   begin
      if Hurt_Flash > 0.0 then
         Color (Cr, 0.78, 0.0, 0.0, Hurt_Flash * 0.6);
         Fill_Rect (Cr, 0.0, 0.0, W, H);
      end if;
      Text (Cr, World.Meta ("currency", "EUR") & " " & Img (Money), 20.0 * S, 14.0 * S, 30.0 * S, Hex ("#7dff8c"));
      Color (Cr, 0.0, 0.0, 0.0, 0.55);
      Fill_Rect (Cr, 20.0 * S, 56.0 * S, 180.0 * S, 12.0 * S);
      Color (Cr, (if PL.HP > 30.0 then Hex ("#e8453c") elsif Blink (4.0) then Hex ("#ff2020") else Hex ("#701010")));
      Fill_Rect (Cr, 20.0 * S, 56.0 * S, 180.0 * S * Float'Max (0.0, PL.HP) / 100.0, 12.0 * S);
      if Armor > 0.0 then
         Color (Cr, Hex ("#3d8fe0"));
         Fill_Rect (Cr, 20.0 * S, 71.0 * S, 180.0 * S * Armor / 100.0, 5.0 * S);
      end if;
      Text (Cr, To_String (Weapon_Names (Weapon)) & (if Weapon > 0 then "  " & Img (Ammo (Weapon)) else ""),
            20.0 * S, 80.0 * S, 17.0 * S, White);
      if Player_Car /= 0 then
         declare
            C : Car renames Cars (Player_Car);
         begin
            Text (Cr, Img (Integer (Physics.Speed (C) * 3.6)) & " km/h   -   car "
                  & Img (Integer'Max (0, Integer (C.HP / Params (C.Kind).HP * 100.0))) & "%",
                  20.0 * S, 104.0 * S, 14.0 * S, (0.87, 0.87, 0.87), Bold => False);
         end;
      end if;
      --  wanted stars
      if Heat > 0.0 then
         declare
            Flash : constant Boolean := Star_Flash > 0.0 and then Blink (8.0);
            C     : constant RGB := (if Flash then White elsif Seen_T > 9.0 then Hex ("#c9b25a") else Yellow);
         begin
            for I in 0 .. 4 loop
               Star (Cr, W - (36.0 + Float (4 - I) * 36.0) * S, 34.0 * S, 15.0 * S, I < Game.Stars, C);
            end loop;
         end;
      end if;
      --  mission
      if Has_Mission then
         declare
            Label : constant String :=
              (case Mis.Kind is
                  when Delivery => "Deliver a car -> " & To_String (Spots (Mis.Dest).Name),
                  when Steal    => (if Mis.Stage > 0 then "Deliver the car -> " & To_String (Spots (Mis.Dest).Name)
                                    else "Steal the marked sports car"),
                  when Hit_Job  => "Eliminate the informant",
                  when Escape   => "Lose the police");
         begin
            Text (Cr, Label, W - 20.0 * S, 58.0 * S, 16.0 * S, Yellow, Right);
            if Mis.Has_Timer then
               declare
                  T : constant Integer := Integer'Max (0, Integer (Float'Ceiling (Mis.Timer)));
                  Sec : constant String := Img (T mod 60);
               begin
                  Text (Cr, Img (T / 60) & ":" & (if T mod 60 < 10 then "0" else "") & Sec,
                        W - 20.0 * S, 82.0 * S, 26.0 * S, (if T < 10 then Hex ("#ff5050") else White), Right);
               end;
            end if;
         end;
      end if;
      --  direction arrow
      Game.Nav_Target (Has_T, TX, TY, T_Phone);
      if Has_T then
         declare
            DX : constant Float := TX - PL.X;
            DY : constant Float := TY - PL.Y;
            D  : constant Float := Hypot (DX, DY);
            A  : constant Float := (if D > 0.01 then Arctan (DY, DX) else 0.0);   --  standing on the target
            R  : constant Float := Float'Min (W, H) * 0.22;
            C  : constant RGB := (if T_Phone then Phone_G else Yellow);
         begin
            if D > 12.0 then
               Save (Cr);
               Gfx.Translate (Cr, W / 2.0 + Cos (A) * R, H / 2.0 + Sin (A) * R);
               Gfx.Rotate (Cr, A);
               Move (Cr, 16.0 * S, 0.0); Line (Cr, -8.0 * S, -10.0 * S);
               Line (Cr, -3.0 * S, 0.0); Line (Cr, -8.0 * S, 10.0 * S);
               Close_Path (Cr);
               Color (Cr, C);
               Fill_Preserve (Cr);
               Color (Cr, 0.0, 0.0, 0.0);
               Width (Cr, 2.0);
               Stroke (Cr);
               Restore (Cr);
               Text (Cr, Img (Integer (D)) & " m", W / 2.0 + Cos (A) * (R + 26.0 * S),
                     H / 2.0 + Sin (A) * (R + 26.0 * S) - 6.0, 12.0 * S, C, Center);
            end if;
         end;
      end if;
      Draw_Minimap (Cr, S, Has_T, TX, TY, T_Phone);
      --  street banner
      if Street_T > 0.0 and then Length (Street_Shown) > 0 then
         declare
            A : constant Float := Float'Min (1.0, Street_T);
         begin
            Text (Cr, To_String (Street_Shown), W / 2.0, H - 92.0 * S, 22.0 * S, White, Center,
                  Alpha => A, Serif => True);
            if District /= Street_Shown then
               Text (Cr, To_String (District), W / 2.0, H - 64.0 * S, 15.0 * S, Hex ("#d8d0b8"), Center,
                     Bold => False, Alpha => A, Serif => True, Italic => True);
            end if;
         end;
      end if;
      --  message box
      if Msg_T > 0.0 then
         declare
            M  : constant String := To_String (Message);
            TW : constant Float := Text_Width (Cr, M, 17.0 * S);
         begin
            Color (Cr, 0.0, 0.0, 0.0, 0.6);
            Fill_Rect (Cr, W / 2.0 - TW / 2.0 - 14.0, 18.0 * S - 8.0, TW + 28.0, 34.0 * S);
            Text (Cr, M, W / 2.0, 18.0 * S, 17.0 * S, White, Center);
         end;
      end if;
      --  big centre text
      if Big_T > 0.0 and then Mode /= Paused then
         declare
            F    : constant Float := Float'Min (1.0, (Big_Max - Big_T) * 4.0);
            Size : constant Float := 80.0 * S * (0.6 + 0.4 * F);
         begin
            Text (Cr, To_String (Big_Text), W / 2.0, H * 0.38 - Size / 2.0, Size, Big_Color, Center, Outline => 8.0);
            Text (Cr, To_String (Big_Sub), W / 2.0, H * 0.38 + 50.0 * S, 22.0 * S, White, Center);
         end;
      end if;
      if Mode = Paused then
         Color (Cr, 0.0, 0.0, 0.0, 0.5);
         Fill_Rect (Cr, 0.0, 0.0, W, H);
         Color (Cr, 0.0, 0.0, 0.0, 0.25);
         Fill_Rect (Cr, 0.0, 0.0, W, H);
         Text (Cr, "PAUSE", W / 2.0, H * 0.12, 60.0 * S, White, Center);
         Text (Cr, "P / Esc / Start: continue     Enter / Y: title screen (change world)",
               W / 2.0, H * 0.12 + 70.0 * S, 16.0 * S, (0.85, 0.85, 0.85), Center, Bold => False, Outline => 0.0);
         Color (Cr, 0.06, 0.07, 0.09, 0.82);
         Round_Rect (Cr, W / 2.0 - 400.0 * S, H * 0.12 + 112.0 * S, 800.0 * S, 236.0 * S, 14.0 * S);
         Fill (Cr);
         Secrets.Draw_Journal (Cr, W / 2.0, H * 0.12 + 130.0 * S, S);
      end if;
   end Draw_HUD;

   ------------------------------------------------------------------ worlds / installer
   Dim  : constant RGB := (0.75, 0.75, 0.75);
   Red  : constant RGB := (1.0, 0.45, 0.4);

   --  progress of the background installer for world W, in a box of width BW centred at X
   procedure Draw_Progress (Cr : Cairo_Context; X, Y, BW, S : Float) is
      use Maps;
      St   : constant String := To_String (Stage);
      BH   : constant Float := 14.0 * S;
      Frac : Float := 0.0;
      Label : Unbounded_String;
   begin
      if St = "download" and then Total > 0 then
         Frac := Float (Done) / Float (Total);
         Label := To_Unbounded_String ("Downloading:" & Natural'Image (Done) & " of" & Natural'Image (Total)
                                       & " " & (if Length (Unit) > 0 then To_String (Unit) else "parts"));
      elsif St = "download" then
         Label := To_Unbounded_String ("Starting download...");
      elsif St = "build" then
         Label := To_Unbounded_String ("Building the map - this takes a minute");
      elsif St = "extract" then
         Label := To_Unbounded_String ("Cutting the city out of the regional map - a few minutes");
      end if;
      Color (Cr, 1.0, 1.0, 1.0, 0.12);
      Round_Rect (Cr, X - BW / 2.0, Y, BW, BH, BH / 2.0);
      Fill (Cr);
      Color (Cr, Yellow);
      if St in "build" | "extract" then   --  indeterminate: a sliding block
         declare
            P : constant Float := (Time * 0.6) - Float'Floor (Time * 0.6);
         begin
            Round_Rect (Cr, X - BW / 2.0 + (BW - BW * 0.25) * P, Y, BW * 0.25, BH, BH / 2.0);
         end;
      else
         Round_Rect (Cr, X - BW / 2.0, Y, Float'Max (BH, BW * Frac), BH, BH / 2.0);
      end if;
      Fill (Cr);
      Text (Cr, To_String (Label), X, Y + BH + 8.0 * S, 15.0 * S, White, Center, Outline => 0.0);
      Text (Cr, To_String (Maps.Message), X, Y + BH + 30.0 * S, 13.0 * S, Dim, Center, Bold => False, Outline => 0.0);
   end Draw_Progress;

   --  shown when no world is installed yet, and while a world is being loaded
   procedure Draw_Setup (Cr : Cairo_Context) is
      use Maps;
      W  : constant Float := Screen_W;
      H  : constant Float := Screen_H;
      S  : constant Float := Float'Max (0.7, Float'Min (1.3, H / 850.0));
      N  : constant Float := Float (World_Id'Pos (World_Id'Last) + 1);
      CW : constant Float := Float'Min (400.0 * S, (W - 40.0 * S - (N - 1.0) * 20.0 * S) / N);
      CH : constant Float := 250.0 * S;
      CY : constant Float := H * 0.5 - 60.0 * S;
   begin
      Color (Cr, Hex ("#1b242b"));
      Paint (Cr);
      --  a faint street grid
      Color (Cr, 1.0, 1.0, 1.0, 0.03);
      Width (Cr, 10.0 * S);
      for I in 0 .. 14 loop
         Move (Cr, Float (I) * W / 10.0 - H * 0.3, 0.0);
         Line (Cr, Float (I) * W / 10.0 + H * 0.2, H);
         Move (Cr, 0.0, Float (I) * H / 7.0 + Float (I mod 3) * 20.0);
         Line (Cr, W, Float (I) * H / 7.0 - 40.0);
      end loop;
      Stroke (Cr);
      Text (Cr, "PAVÉ", W / 2.0, H * 0.1, 96.0 * S, Yellow, Center, Outline => 8.0);
      Text (Cr, "a top-down crime caper on real city streets", W / 2.0, H * 0.1 + 112.0 * S, 20.0 * S,
            Hex ("#d8d0b8"), Center, Bold => False, Outline => 0.0, Serif => True, Italic => True);
      if Loading then
         Text (Cr, "Loading " & Title (Selected) & "...", W / 2.0, H * 0.55, 30.0 * S, White, Center,
               Outline => 0.0);
         return;
      end if;
      Text (Cr, (if Any_Installed then "Choose your city"
                 else "First, download a city map from OpenStreetMap"),
            W / 2.0, CY - 70.0 * S, 24.0 * S, White, Center, Outline => 0.0);
      for Wd in World_Id loop
         declare
            X   : constant Float := W / 2.0 - (N * CW + (N - 1.0) * 20.0 * S) / 2.0
              + Float (World_Id'Pos (Wd)) * (CW + 20.0 * S);
            Sel : constant Boolean := Wd = Selected;
            TX  : constant Float := X + CW / 2.0;
         begin
            Color (Cr, (if Sel then (0.17, 0.2, 0.23) else (0.12, 0.15, 0.17)));
            Round_Rect (Cr, X, CY, CW, CH, 14.0 * S);
            Fill_Preserve (Cr);
            Color (Cr, (if Sel then Yellow else (0.35, 0.38, 0.4)));
            Width (Cr, (if Sel then 3.0 else 1.5));
            Stroke (Cr);
            Text (Cr, Integer'Image (World_Id'Pos (Wd) + 1) & "   " & Title (Wd), TX, CY + 22.0 * S, 26.0 * S,
                  (if Sel then Yellow else White), Center, Outline => 0.0);
            Text (Cr, About (Wd), TX, CY + 70.0 * S, 14.0 * S, (0.9, 0.9, 0.9), Center, Bold => False,
                  Outline => 0.0);
            Text (Cr, Download_Info (Wd), TX, CY + 94.0 * S, 13.0 * S, Dim, Center, Bold => False,
                  Outline => 0.0);
            if Installing and then Install_World = Wd then
               Draw_Progress (Cr, TX, CY + 140.0 * S, CW - 60.0 * S, S);
            elsif Installed (Wd) then
               Text (Cr, "Installed - press ENTER to play", TX, CY + 150.0 * S, 17.0 * S, Phone_G, Center,
                     Outline => 0.0);
            elsif Failed and then Install_World = Wd then
               Text (Cr, To_String (Maps.Message), TX, CY + 140.0 * S, 13.0 * S, Red, Center, Bold => False,
                     Outline => 0.0);
               Text (Cr, "Press ENTER to try again", TX, CY + 168.0 * S, 16.0 * S, White, Center, Outline => 0.0);
            elsif Sel then
               Text (Cr, (if To_String (Stage) = "cancelled" and then Install_World = Wd
                          then "Paused - ENTER to resume"
                          else "Press ENTER to download"),
                     TX, CY + 150.0 * S, 17.0 * S, White, Center, Outline => 0.0);
            end if;
         end;
      end loop;
      Text (Cr, "Left / Right or 1 - 3: choose     Enter: download / play     Esc: pause the download",
            W / 2.0, CY + CH + 30.0 * S, 15.0 * S, Dim, Center, Bold => False, Outline => 0.0);
      if Gamepad.Connected then
         Text (Cr, "Controller:  D-pad choose     A download / play     B pause the download",
               W / 2.0, CY + CH + 54.0 * S, 15.0 * S, Dim, Center, Bold => False, Outline => 0.0);
      end if;
      Text (Cr, "A paused or interrupted download continues where it stopped - you can close the game.",
            W / 2.0, CY + CH + 84.0 * S, 13.0 * S, (0.6, 0.6, 0.6), Center, Bold => False, Outline => 0.0);
      if not Can_Install then
         Text (Cr, "python3 is needed to download maps (or run tools/get_map.py on another machine).",
               W / 2.0, CY + CH + 110.0 * S, 14.0 * S, Red, Center, Bold => False, Outline => 0.0);
      end if;
      Text (Cr, "Map data (c) OpenStreetMap contributors (ODbL), downloaded through the Overpass API",
            W / 2.0, H - 30.0 * S, 12.0 * S, (0.6, 0.6, 0.6), Center, Bold => False, Outline => 0.0);
   end Draw_Setup;

   --  the world line on the title screen
   procedure Draw_World_Choice (Cr : Cairo_Context; Y : Float; S : Float) is
      use Maps;
      W : constant Float := Screen_W;
   begin
      Text (Cr, "<   " & Title (Selected) & "   >", W / 2.0, Y, 24.0 * S,
            (if Selected = Current then White else Yellow), Center, Outline => 0.0);
      if Installing and then Install_World = Selected then
         Draw_Progress (Cr, W / 2.0, Y + 36.0 * S, 420.0 * S, S);
      elsif Selected = Current then
         Text (Cr, "World  -  Left / Right to change", W / 2.0, Y + 34.0 * S, 14.0 * S, Dim, Center,
               Bold => False, Outline => 0.0);
      elsif Installed (Selected) then
         Text (Cr, About (Selected) & "  -  press ENTER to play here", W / 2.0, Y + 34.0 * S, 15.0 * S,
               Phone_G, Center, Bold => False, Outline => 0.0);
      elsif Failed and then Install_World = Selected then
         Text (Cr, To_String (Maps.Message) & "  -  ENTER to try again", W / 2.0, Y + 34.0 * S, 14.0 * S, Red,
               Center, Bold => False, Outline => 0.0);
      elsif Installing then
         Text (Cr, "Another world is downloading - wait for it to finish", W / 2.0, Y + 34.0 * S, 14.0 * S,
               Dim, Center, Bold => False, Outline => 0.0);
      else
         Text (Cr, "Not installed  -  press ENTER to download it in the background (" & Download_Info (Selected)
               & ")", W / 2.0, Y + 34.0 * S, 14.0 * S, Dim, Center, Bold => False, Outline => 0.0);
      end if;
   end Draw_World_Choice;


   procedure Draw_Title (Cr : Cairo_Context) is
      W : constant Float := Screen_W;
      H : constant Float := Screen_H;
      S : constant Float := Float'Max (0.7, Float'Min (1.3, H / 850.0));
      Y : Float := H * 0.5 - 330.0 * S;
      type Row is record
         K, V : Unbounded_String;
      end record;
      function "+" (S : String) return Unbounded_String renames To_Unbounded_String;
      Rows : constant array (1 .. 7) of Row :=
        ((+"WASD / Arrows", +"walk - drive"),
         (+"Shift", +"sprint"),
         (+"F / E / Enter", +"steal a car - get in / out"),
         (+"Space", +"shoot (on foot) - handbrake (in car)"),
         (+"Ctrl / X / Mouse", +"shoot (mouse aims on foot, drive-by in car)"),
         (+"Q / Tab / 1-3", +"switch weapon"),
         (+"H - M - P / Esc", +"horn - mute - pause"));
   begin
      Color (Cr, 0.0, 0.0, 0.0, 0.62);
      Fill_Rect (Cr, 0.0, 0.0, W, H);
      Text (Cr, "PAVÉ", W / 2.0, Y, 110.0 * S, Yellow, Center, Outline => 10.0);
      Y := Y + 128.0 * S;
      Text (Cr, "a top-down crime caper on the streets of " & World.Meta ("city", "Paris"), W / 2.0, Y, 22.0 * S,
            Hex ("#d8d0b8"), Center, Bold => False, Outline => 0.0, Serif => True, Italic => True);
      Y := Y + 56.0 * S;
      for R of Rows loop
         Text (Cr, To_String (R.K), W / 2.0 - 12.0 * S, Y, 16.0 * S, Yellow, Right, Outline => 0.0);
         Text (Cr, To_String (R.V), W / 2.0 + 12.0 * S, Y, 16.0 * S, (0.93, 0.93, 0.93), Left,
               Bold => False, Outline => 0.0);
         Y := Y + 25.0 * S;
      end loop;
      Y := Y + 8.0 * S;
      Text (Cr, "Controller: LS move/steer - RT shoot/gas - LT brake - RS aim - A sprint/handbrake",
            W / 2.0, Y, 14.0 * S, (0.8, 0.8, 0.8), Center, Bold => False, Outline => 0.0);
      Y := Y + 21.0 * S;
      Text (Cr, "Y enter/exit - X drive-by - B horn - LB/RB weapon - Start pause - Back mute",
            W / 2.0, Y, 14.0 * S, (0.8, 0.8, 0.8), Center, Bold => False, Outline => 0.0);
      Y := Y + 32.0 * S;
      Text (Cr, "Answer ringing phones (green markers) for jobs. Earn 50,000 " & World.Meta ("currency", "EUR")
            & " to own " & World.Meta ("city", "Paris") & ".",
            W / 2.0, Y, 16.0 * S, (0.93, 0.93, 0.93), Center, Bold => False, Outline => 0.0);
      Y := Y + 44.0 * S;
      Draw_World_Choice (Cr, Y, S);
      Y := Y + (if Maps.Installing and then Maps.Install_World = Maps.Selected then 110.0 else 76.0) * S;
      if not Blink (2.0) and then Maps.Selected = Maps.Current then
         Text (Cr, (if Game.Started_Once then "Press ENTER to continue" else "Press ENTER to start"),
               W / 2.0, Y, 24.0 * S, White, Center, Outline => 0.0);
      end if;
      if Gamepad.Connected then
         Text (Cr, "Controller connected: " & To_String (Gamepad.Name) & " - press START",
               W / 2.0, H - 58.0 * S, 14.0 * S, (0.31, 1.0, 0.47), Center, Bold => False, Outline => 0.0);
      end if;
      Text (Cr, "Map data (c) OpenStreetMap contributors (ODbL)", W / 2.0, H - 30.0 * S, 12.0 * S,
            (0.6, 0.6, 0.6), Center, Bold => False, Outline => 0.0);
   end Draw_Title;

   procedure Draw (Cr : Cairo_Context) is
   begin
      Set_Line_Join (Cr, Cairo_Line_Join_Round);
      Draw_World (Cr);
      if Mode = Title then
         Draw_Title (Cr);
      else
         if Show_HUD then
            Draw_HUD (Cr);
         end if;
         Secrets.Draw_Overlay (Cr);
      end if;
   end Draw;

end Render;
