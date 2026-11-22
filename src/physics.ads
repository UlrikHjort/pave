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

--  Car dynamics, pedestrian movement and the low-level driving AI.
with State; use State;

package Physics is

   function Alloc_Car (K : Car_Type; X, Y, A : Float) return Car_Ref;   --  0 if pool full
   function Alloc_Ped (X, Y : Float;
                       Cop, Is_Player, Target : Boolean := False;
                       HP : Float := 100.0) return Ped_Ref;

   function Speed (C : Car) return Float;
   function Fwd_Speed (C : Car) return Float;
   procedure Damage (C : in out Car; N : Float; By : Culprit);

   type Circle is record
      X, Y, R : Float;
   end record;
   type Circle_Array is array (1 .. 6) of Circle;
   procedure Circles (C : Car; Out_C : out Circle_Array; N : out Natural);

   --  integrates one step; Impact = strongest wall impact speed (0 if none)
   procedure Update_Car (C : in out Car; DT : Float; Impact : out Float);
   function Fits (C : Car) return Boolean;   --  not overlapping buildings / water

   procedure Ped_Move_By (P : in out Ped; DX, DY : Float);
   procedure Ped_Wander (P : in out Ped; DT : Float);
   procedure Ped_Scare (P : in out Ped; X, Y, T : Float);
   procedure Ped_Update (P : in out Ped; DT : Float);

   --  driving AI
   procedure Extend_Random (C : in out Car);
   procedure AI_Target (C : in out Car; Look : Float; TX, TY : out Float);
   function Bend (C : Car) return Float;
   procedure Steer_To (C : in out Car; TX, TY, Desired, DT : Float);

end Physics;
