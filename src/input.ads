-- ***************************************************************************
--                      PAVÉ - Input
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

--  Keyboard / mouse state. Keys are polled each frame; Hit is edge-triggered.
with Gdk.Types;

package Input is

   type Key is (K_Up, K_Down, K_Left, K_Right, K_Space, K_Shift, K_Ctrl, K_X,
                K_F, K_Enter, K_Q, K_Tab, K_H, K_M, K_P, K_Esc,
                K_1, K_2, K_3, K_4, K_5, K_6, K_None);

   Down : array (Key) of Boolean := (others => False);
   Hit  : array (Key) of Boolean := (others => False);

   Mouse_X, Mouse_Y : Float := 0.0;
   Mouse_Down       : Boolean := False;
   Mouse_Clicked    : Boolean := False;

   procedure Press (K : Gdk.Types.Gdk_Key_Type);
   procedure Release (K : Gdk.Types.Gdk_Key_Type);
   procedure Release_All;
   procedure End_Frame;

   --  the last letters typed (upper case), for cheat words
   Typed : String (1 .. 16) := (others => ' ');
   function Typed_Ends_With (W : String) return Boolean;
   procedure Clear_Typed;

end Input;
