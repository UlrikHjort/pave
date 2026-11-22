-- ***************************************************************************
--                      PAVÉ - Util
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
with Ada.Numerics.Float_Random;

package body Util is

   Gen : Ada.Numerics.Float_Random.Generator;

   function Clamp (V, Lo, Hi : Float) return Float is
     (if V < Lo then Lo elsif V > Hi then Hi else V);

   function Ang_Diff (A, B : Float) return Float is
      D : Float := B - A;
   begin
      while D > Pi loop
         D := D - 2.0 * Pi;
      end loop;
      while D < -Pi loop
         D := D + 2.0 * Pi;
      end loop;
      return D;
   end Ang_Diff;

   function Hypot (X, Y : Float) return Float is (Sqrt (X * X + Y * Y));

   function Sign (V : Float) return Float is
     (if V > 0.0 then 1.0 elsif V < 0.0 then -1.0 else 0.0);

   function Rand return Float is
      R : constant Float := Ada.Numerics.Float_Random.Random (Gen);
   begin
      return (if R >= 1.0 then 0.999_999 else R);
   end Rand;

   function Rand (A, B : Float) return Float is (A + Rand * (B - A));

   function Rand_Int (N : Positive) return Natural is
      V : constant Natural := Natural (Float'Floor (Rand * Float (N)));
   begin
      return (if V >= N then N - 1 else V);
   end Rand_Int;

   procedure Seed (N : Integer) is
   begin
      Ada.Numerics.Float_Random.Reset (Gen, N);
   end Seed;

   function Hash (N : Float) return Float is
      V : constant Float := Sin (N * 127.1) * 43_758.545;
   begin
      return V - Float'Floor (V);
   end Hash;

   function Shade (C : RGB; F : Float) return RGB is
   begin
      if F < 0.0 then
         return (C.R * (1.0 + F), C.G * (1.0 + F), C.B * (1.0 + F));
      else
         return (C.R + (1.0 - C.R) * F, C.G + (1.0 - C.G) * F, C.B + (1.0 - C.B) * F);
      end if;
   end Shade;

   function Hex (S : String) return RGB is
      function Digit (C : Character) return Natural is
        (case C is
            when '0' .. '9' => Character'Pos (C) - Character'Pos ('0'),
            when 'a' .. 'f' => Character'Pos (C) - Character'Pos ('a') + 10,
            when 'A' .. 'F' => Character'Pos (C) - Character'Pos ('A') + 10,
            when others => 0);
      function Byte (I : Positive) return Float is
        (Float (Digit (S (I)) * 16 + Digit (S (I + 1))) / 255.0);
      F : constant Positive := S'First + 1;
   begin
      return (Byte (F), Byte (F + 2), Byte (F + 4));
   end Hex;

   function HSL (H, S, L : Float) return RGB is
      SS : constant Float := S / 100.0;
      LL : constant Float := L / 100.0;
      C  : constant Float := (1.0 - abs (2.0 * LL - 1.0)) * SS;
      HP : constant Float := H / 60.0;
      X  : constant Float := C * (1.0 - abs (HP - 2.0 * Float'Floor (HP / 2.0) - 1.0));
      M  : constant Float := LL - C / 2.0;
      R, G, B : Float;
   begin
      if HP < 1.0 then
         R := C; G := X; B := 0.0;
      elsif HP < 2.0 then
         R := X; G := C; B := 0.0;
      elsif HP < 3.0 then
         R := 0.0; G := C; B := X;
      elsif HP < 4.0 then
         R := 0.0; G := X; B := C;
      elsif HP < 5.0 then
         R := X; G := 0.0; B := C;
      else
         R := C; G := 0.0; B := X;
      end if;
      return (R + M, G + M, B + M);
   end HSL;

begin
   Ada.Numerics.Float_Random.Reset (Gen);
end Util;
