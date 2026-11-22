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

--  Game controller support via the Linux joystick API (/dev/input/jsN).
--  Tuned for the xpad driver layout (Xbox 360 / compatible pads).
--  Set PAVE_JOYSTICK=/dev/input/jsN to force a specific device.
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Gamepad is

   type Button is (A, B, X, Y, LB, RB, Back, Start, Guide, LS, RS,
                   D_Up, D_Down, D_Left, D_Right);

   Connected : Boolean := False;
   Name      : Unbounded_String;

   --  sticks in -1 .. 1 after deadzone (Y positive = down), triggers 0 .. 1
   LX, LY, RX, RY : Float := 0.0;
   LT, RT         : Float := 0.0;

   Down : array (Button) of Boolean := (others => False);
   Hit  : array (Button) of Boolean := (others => False);   --  pressed this frame

   Changed : Boolean := False;   --  set when connected / disconnected (for a HUD message)

   procedure Poll (DT : Float);  --  read all pending events; retries connection
   procedure End_Frame;

end Gamepad;
