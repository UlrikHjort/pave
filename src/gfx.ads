-- ***************************************************************************
--                      PAVÉ - Gfx
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

--  Thin convenience layer over Cairo using Float coordinates.
with Cairo; use Cairo;
with Util;  use Util;
with World;

package Gfx is

   procedure Color (Cr : Cairo_Context; C : RGB; A : Float := 1.0);
   procedure Color (Cr : Cairo_Context; R, G, B : Float; A : Float := 1.0);
   procedure Move (Cr : Cairo_Context; X, Y : Float);
   procedure Line (Cr : Cairo_Context; X, Y : Float);
   procedure Rect (Cr : Cairo_Context; X, Y, W, H : Float);
   procedure Fill_Rect (Cr : Cairo_Context; X, Y, W, H : Float);
   procedure Circle (Cr : Cairo_Context; X, Y, R : Float);
   procedure Fill_Circle (Cr : Cairo_Context; X, Y, R : Float);
   procedure Ellipse (Cr : Cairo_Context; X, Y, RX, RY, Rot : Float);
   procedure Round_Rect (Cr : Cairo_Context; X, Y, W, H, R : Float);
   procedure Poly_Path (Cr : Cairo_Context; P : World.Poly);
   procedure Line_Path (Cr : Cairo_Context; P : World.Poly);
   procedure Translate (Cr : Cairo_Context; X, Y : Float);
   procedure Rotate (Cr : Cairo_Context; A : Float);
   procedure Scale (Cr : Cairo_Context; S : Float);
   procedure Width (Cr : Cairo_Context; W : Float);

   type Align is (Left, Center, Right);
   --  Draws text whose top edge is at Y (like CSS textBaseline=top), with a dark outline.
   procedure Text (Cr      : Cairo_Context;
                   S       : String;
                   X, Y    : Float;
                   Size    : Float;
                   C       : RGB;
                   Al      : Align := Left;
                   Bold    : Boolean := True;
                   Alpha   : Float := 1.0;
                   Outline : Float := 4.0;
                   Serif   : Boolean := False;
                   Italic  : Boolean := False);
   function Text_Width (Cr : Cairo_Context; S : String; Size : Float;
                        Bold : Boolean := True; Serif : Boolean := False) return Float;

end Gfx;
