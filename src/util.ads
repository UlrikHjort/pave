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

--  Small math, random and colour helpers shared by the whole game.
with Ada.Numerics;

package Util is

   type Float_Array is array (Natural range <>) of Float;
   type Float_Array_Access is access Float_Array;
   type Int_Array is array (Natural range <>) of Integer;
   type Int_Array_Access is access Int_Array;

   type RGB is record
      R, G, B : Float;
   end record;

   Pi : constant := Ada.Numerics.Pi;

   function Clamp (V, Lo, Hi : Float) return Float;
   function Ang_Diff (A, B : Float) return Float;   --  signed B - A in (-Pi, Pi]
   function Hypot (X, Y : Float) return Float;
   function Sign (V : Float) return Float;
   function Rand return Float;                       --  [0, 1)
   function Rand (A, B : Float) return Float;
   function Rand_Int (N : Positive) return Natural;  --  0 .. N - 1
   procedure Seed (N : Integer);   --  make Rand repeatable
   function Hash (N : Float) return Float;            --  deterministic pseudo random [0,1)
   function Shade (C : RGB; F : Float) return RGB;   --  F < 0 darker, F > 0 lighter
   function Hex (S : String) return RGB;             --  "#rrggbb"
   function HSL (H, S, L : Float) return RGB;        --  H degrees, S/L 0..100

end Util;
