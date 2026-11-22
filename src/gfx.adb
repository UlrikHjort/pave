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

with Glib; use Glib;
with Gtkada.Types;

package body Gfx is

   function D (V : Float) return Gdouble is (Gdouble (V));

   procedure Color (Cr : Cairo_Context; C : RGB; A : Float := 1.0) is
   begin
      Set_Source_Rgba (Cr, D (C.R), D (C.G), D (C.B), D (A));
   end Color;

   procedure Color (Cr : Cairo_Context; R, G, B : Float; A : Float := 1.0) is
   begin
      Set_Source_Rgba (Cr, D (R), D (G), D (B), D (A));
   end Color;

   procedure Move (Cr : Cairo_Context; X, Y : Float) is
   begin
      Move_To (Cr, D (X), D (Y));
   end Move;

   procedure Line (Cr : Cairo_Context; X, Y : Float) is
   begin
      Line_To (Cr, D (X), D (Y));
   end Line;

   procedure Rect (Cr : Cairo_Context; X, Y, W, H : Float) is
   begin
      Rectangle (Cr, D (X), D (Y), D (W), D (H));
   end Rect;

   procedure Fill_Rect (Cr : Cairo_Context; X, Y, W, H : Float) is
   begin
      Rectangle (Cr, D (X), D (Y), D (W), D (H));
      Fill (Cr);
   end Fill_Rect;

   procedure Circle (Cr : Cairo_Context; X, Y, R : Float) is
   begin
      New_Sub_Path (Cr);
      Arc (Cr, D (X), D (Y), D (R), 0.0, 2.0 * Util.Pi);
   end Circle;

   procedure Fill_Circle (Cr : Cairo_Context; X, Y, R : Float) is
   begin
      New_Path (Cr);
      Arc (Cr, D (X), D (Y), D (R), 0.0, 2.0 * Util.Pi);
      Fill (Cr);
   end Fill_Circle;

   procedure Ellipse (Cr : Cairo_Context; X, Y, RX, RY, Rot : Float) is
   begin
      Save (Cr);
      Cairo.Translate (Cr, D (X), D (Y));
      Cairo.Rotate (Cr, D (Rot));
      Cairo.Scale (Cr, D (RX), D (RY));
      New_Sub_Path (Cr);
      Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Util.Pi);
      Restore (Cr);
   end Ellipse;

   procedure Round_Rect (Cr : Cairo_Context; X, Y, W, H, R : Float) is
      Q : constant Gdouble := Gdouble (Util.Pi / 2.0);
   begin
      New_Sub_Path (Cr);
      Arc (Cr, D (X + W - R), D (Y + R), D (R), -Q, 0.0);
      Arc (Cr, D (X + W - R), D (Y + H - R), D (R), 0.0, Q);
      Arc (Cr, D (X + R), D (Y + H - R), D (R), Q, 2.0 * Q);
      Arc (Cr, D (X + R), D (Y + R), D (R), 2.0 * Q, 3.0 * Q);
      Close_Path (Cr);
   end Round_Rect;

   procedure Poly_Path (Cr : Cairo_Context; P : World.Poly) is
      C : Util.Float_Array renames World.Coords.all;
   begin
      Move_To (Cr, D (C (P.First)), D (C (P.First + 1)));
      for K in 1 .. P.Count - 1 loop
         Line_To (Cr, D (C (P.First + 2 * K)), D (C (P.First + 2 * K + 1)));
      end loop;
      Close_Path (Cr);
   end Poly_Path;

   procedure Line_Path (Cr : Cairo_Context; P : World.Poly) is
      C : Util.Float_Array renames World.Coords.all;
   begin
      Move_To (Cr, D (C (P.First)), D (C (P.First + 1)));
      for K in 1 .. P.Count - 1 loop
         Line_To (Cr, D (C (P.First + 2 * K)), D (C (P.First + 2 * K + 1)));
      end loop;
   end Line_Path;

   procedure Translate (Cr : Cairo_Context; X, Y : Float) is
   begin
      Cairo.Translate (Cr, D (X), D (Y));
   end Translate;

   procedure Rotate (Cr : Cairo_Context; A : Float) is
   begin
      Cairo.Rotate (Cr, D (A));
   end Rotate;

   procedure Scale (Cr : Cairo_Context; S : Float) is
   begin
      Cairo.Scale (Cr, D (S), D (S));
   end Scale;

   procedure Width (Cr : Cairo_Context; W : Float) is
   begin
      Set_Line_Width (Cr, D (W));
   end Width;

   procedure Font (Cr : Cairo_Context; Size : Float; Bold, Serif, Italic : Boolean) is
   begin
      Select_Font_Face
        (Cr, (if Serif then "Serif" else "Sans"),
         (if Italic then Cairo_Font_Slant_Italic else Cairo_Font_Slant_Normal),
         (if Bold then Cairo_Font_Weight_Bold else Cairo_Font_Weight_Normal));
      Set_Font_Size (Cr, D (Size));
   end Font;

   function Measure (Cr : Cairo_Context; S : String) return Float is
      Ext : aliased Cairo_Text_Extents;
      P   : Gtkada.Types.Chars_Ptr := Gtkada.Types.New_String (S);
   begin
      Text_Extents (Cr, P, Ext'Access);
      Gtkada.Types.Free (P);
      return Float (Ext.X_Advance);
   end Measure;

   function Text_Width (Cr : Cairo_Context; S : String; Size : Float;
                        Bold : Boolean := True; Serif : Boolean := False) return Float is
   begin
      Font (Cr, Size, Bold, Serif, False);
      return Measure (Cr, S);
   end Text_Width;

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
                   Italic  : Boolean := False) is
      TX : Float := X;
   begin
      if S'Length = 0 then
         return;
      end if;
      Font (Cr, Size, Bold, Serif, Italic);
      case Al is
         when Left   => null;
         when Center => TX := X - Measure (Cr, S) / 2.0;
         when Right  => TX := X - Measure (Cr, S);
      end case;
      New_Path (Cr);
      Move_To (Cr, D (TX), D (Y + Size * 0.82));
      Text_Path (Cr, S);
      if Outline > 0.0 then
         Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, D (0.85 * Alpha));
         Set_Line_Width (Cr, D (Outline));
         Set_Line_Join (Cr, Cairo_Line_Join_Round);
         Stroke_Preserve (Cr);
      end if;
      Color (Cr, C, Alpha);
      Fill (Cr);
   end Text;

end Gfx;
