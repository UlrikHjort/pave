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

with Gdk.Types.Keysyms; use Gdk.Types.Keysyms;

package body Input is

   function Map (K : Gdk.Types.Gdk_Key_Type) return Key is
   begin
      case K is
         when GDK_Up | GDK_LC_w | GDK_W | GDK_KP_Up          => return K_Up;
         when GDK_Down | GDK_LC_s | GDK_S | GDK_KP_Down      => return K_Down;
         when GDK_Left | GDK_LC_a | GDK_A | GDK_KP_Left      => return K_Left;
         when GDK_Right | GDK_LC_d | GDK_D | GDK_KP_Right    => return K_Right;
         when GDK_space                                      => return K_Space;
         when GDK_Shift_L | GDK_Shift_R                      => return K_Shift;
         when GDK_Control_L | GDK_Control_R                  => return K_Ctrl;
         when GDK_LC_x | GDK_X                               => return K_X;
         when GDK_LC_f | GDK_F | GDK_LC_e | GDK_E            => return K_F;
         when GDK_Return | GDK_KP_Enter                      => return K_Enter;
         when GDK_LC_q | GDK_Q                               => return K_Q;
         when GDK_Tab                                        => return K_Tab;
         when GDK_LC_h | GDK_H                               => return K_H;
         when GDK_LC_m | GDK_M                               => return K_M;
         when GDK_LC_p | GDK_P                               => return K_P;
         when GDK_Escape                                     => return K_Esc;
         when GDK_1                                          => return K_1;
         when GDK_2                                          => return K_2;
         when GDK_3                                          => return K_3;
         when GDK_4                                          => return K_4;
         when GDK_5                                          => return K_5;
         when GDK_6                                          => return K_6;
         when others                                         => return K_None;
      end case;
   end Map;

   procedure Press (K : Gdk.Types.Gdk_Key_Type) is
      M : constant Key := Map (K);
      V : constant Natural := Natural (K);
   begin
      if V in 16#41# .. 16#5A# or else V in 16#61# .. 16#7A# then
         Typed (1 .. Typed'Last - 1) := Typed (2 .. Typed'Last);
         Typed (Typed'Last) := Character'Val (if V >= 16#61# then V - 32 else V);
      end if;
      if not Down (M) then
         Hit (M) := True;
      end if;
      Down (M) := True;
   end Press;

   procedure Release (K : Gdk.Types.Gdk_Key_Type) is
   begin
      Down (Map (K)) := False;
   end Release;

   procedure Release_All is
   begin
      Down := (others => False);
      Mouse_Down := False;
   end Release_All;

   function Typed_Ends_With (W : String) return Boolean is
     (W'Length <= Typed'Length and then Typed (Typed'Last - W'Length + 1 .. Typed'Last) = W);

   procedure Clear_Typed is
   begin
      Typed := (others => ' ');
   end Clear_Typed;

   procedure End_Frame is
   begin
      Hit := (others => False);
      Mouse_Clicked := False;
   end End_Frame;

end Input;
