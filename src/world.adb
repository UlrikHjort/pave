-- ***************************************************************************
--                      PAVÉ - World
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

with Ada.Streams;            use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Directories;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Ada.Containers.Generic_Array_Sort;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Interfaces;              use Interfaces;
with System;
with Glib;                    use Glib;
with Cairo;                   use Cairo;
with Cairo.Image_Surface;     use Cairo.Image_Surface;
with Cairo.Surface;

package body World is

   ------------------------------------------------------------------ binary reader
   Buf : access Stream_Element_Array;
   Pos : Stream_Element_Offset;

   function To_I32 is new Ada.Unchecked_Conversion (Unsigned_32, Integer_32);
   function To_F32 is new Ada.Unchecked_Conversion (Unsigned_32, Float);

   function U32 return Unsigned_32 is
      V : Unsigned_32 := 0;
   begin
      for K in reverse 0 .. 3 loop
         V := Shift_Left (V, 8) or Unsigned_32 (Buf (Pos + Stream_Element_Offset (K)));
      end loop;
      Pos := Pos + 4;
      return V;
   end U32;

   function RI return Integer is (Integer (To_I32 (U32)));
   function RF return Float is (To_F32 (U32));

   function RS return Unbounded_String is
      N : constant Natural := RI;
      S : String (1 .. N);
   begin
      for K in 1 .. N loop
         S (K) := Character'Val (Buf (Pos));
         Pos := Pos + 1;
      end loop;
      return To_Unbounded_String (S);
   end RS;

   --  coordinates are appended to a growable temporary array
   Tmp       : Float_Array_Access;
   Tmp_Count : Natural := 0;

   procedure Push (V : Float) is
   begin
      if Tmp_Count > Tmp'Last then
         declare
            N : constant Float_Array_Access := new Float_Array (0 .. Tmp'Length * 2 - 1);
         begin
            N (0 .. Tmp'Last) := Tmp.all;
            Tmp := N;
         end;
      end if;
      Tmp (Tmp_Count) := V;
      Tmp_Count := Tmp_Count + 1;
   end Push;

   function Read_Poly return Poly is
      N : constant Natural := RI;
      P : constant Poly := (First => Tmp_Count, Count => N);
   begin
      for K in 1 .. 2 * N loop
         Push (RF);
      end loop;
      return P;
   end Read_Poly;

   function Box_Of (P : Poly) return BBox is
      B : BBox := (1.0E9, 1.0E9, -1.0E9, -1.0E9);
   begin
      for K in 0 .. P.Count - 1 loop
         declare
            X : constant Float := Tmp (P.First + 2 * K);
            Y : constant Float := Tmp (P.First + 2 * K + 1);
         begin
            B.X0 := Float'Min (B.X0, X); B.X1 := Float'Max (B.X1, X);
            B.Y0 := Float'Min (B.Y0, Y); B.Y1 := Float'Max (B.Y1, Y);
         end;
      end loop;
      return B;
   end Box_Of;

   procedure Orient (P : Poly; Clockwise : Boolean) is
      A : Float := 0.0;
   begin
      for K in 0 .. P.Count - 1 loop
         declare
            J : constant Natural := P.First + 2 * K;
            Q : constant Natural := P.First + 2 * ((K + 1) mod P.Count);
         begin
            A := A + Tmp (J) * Tmp (Q + 1) - Tmp (Q) * Tmp (J + 1);
         end;
      end loop;
      if (A > 0.0) /= Clockwise then      --  reverse the points in place
         for K in 0 .. P.Count / 2 - 1 loop
            declare
               I1 : constant Natural := P.First + 2 * K;
               I2 : constant Natural := P.First + 2 * (P.Count - 1 - K);
               TX : constant Float := Tmp (I1);
               TY : constant Float := Tmp (I1 + 1);
            begin
               Tmp (I1) := Tmp (I2); Tmp (I1 + 1) := Tmp (I2 + 1);
               Tmp (I2) := TX; Tmp (I2 + 1) := TY;
            end;
         end loop;
      end if;
   end Orient;

   function Read_Shapes return Shape_Access is
      N : constant Natural := RI;
      S : constant Shape_Access := new Shape_Array (0 .. N - 1);
   begin
      for K in S'Range loop
         S (K).P := Read_Poly;
         S (K).BB := Box_Of (S (K).P);
      end loop;
      return S;
   end Read_Shapes;

   ------------------------------------------------------------------ graphs
   GB : constant Float := 32.0;    --  graph bucket size

   type Graph is record
      N                        : Natural := 0;
      Xs, Ys                   : Float_Array_Access;
      Start, Adj, UStart, UAdj : Int_Array_Access;
      BW, BH                   : Natural := 0;
      B_Start, B_List          : Int_Array_Access;
   end record;
   G : array (Graph_Kind) of Graph;

   procedure Read_Graph (K : Graph_Kind) is
      R : Graph renames G (K);
      M : Natural;
   begin
      R.N := RI;
      R.Xs := new Float_Array (0 .. R.N - 1);
      R.Ys := new Float_Array (0 .. R.N - 1);
      for I in 0 .. R.N - 1 loop
         R.Xs (I) := RF;
      end loop;
      for I in 0 .. R.N - 1 loop
         R.Ys (I) := RF;
      end loop;
      R.Start := new Int_Array (0 .. R.N);
      for I in 0 .. R.N loop
         R.Start (I) := RI;
      end loop;
      M := RI;
      R.Adj := new Int_Array (0 .. Integer'Max (M, 1) - 1);
      for I in 0 .. M - 1 loop
         R.Adj (I) := RI;
      end loop;
      R.UStart := new Int_Array (0 .. R.N);
      for I in 0 .. R.N loop
         R.UStart (I) := RI;
      end loop;
      M := RI;
      R.UAdj := new Int_Array (0 .. Integer'Max (M, 1) - 1);
      for I in 0 .. M - 1 loop
         R.UAdj (I) := RI;
      end loop;
      --  spatial buckets (CSR)
      R.BW := Natural (Float'Ceiling (W / GB)) + 1;
      R.BH := Natural (Float'Ceiling (H / GB)) + 1;
      declare
         Cnt : Int_Array (0 .. R.BW * R.BH) := (others => 0);
         function B_Of (I : Natural) return Natural is
            BX : constant Integer := Integer'Max (0, Integer'Min (R.BW - 1, Integer (Float'Floor (R.Xs (I) / GB))));
            BY : constant Integer := Integer'Max (0, Integer'Min (R.BH - 1, Integer (Float'Floor (R.Ys (I) / GB))));
         begin
            return BY * R.BW + BX;
         end B_Of;
      begin
         for I in 0 .. R.N - 1 loop
            Cnt (B_Of (I) + 1) := Cnt (B_Of (I) + 1) + 1;
         end loop;
         for I in 1 .. Cnt'Last loop
            Cnt (I) := Cnt (I) + Cnt (I - 1);
         end loop;
         R.B_Start := new Int_Array'(Cnt);
         R.B_List := new Int_Array (0 .. Integer'Max (R.N, 1) - 1);
         declare
            Fill : Int_Array := Cnt;
         begin
            for I in 0 .. R.N - 1 loop
               R.B_List (Fill (B_Of (I))) := I;
               Fill (B_Of (I)) := Fill (B_Of (I)) + 1;
            end loop;
         end;
      end;
   end Read_Graph;

   function Node_Count (K : Graph_Kind) return Natural is (G (K).N);
   function NX (K : Graph_Kind; I : Natural) return Float is (G (K).Xs (I));
   function NY (K : Graph_Kind; I : Natural) return Float is (G (K).Ys (I));
   function Degree (K : Graph_Kind; I : Natural) return Natural is
     (G (K).Start (I + 1) - G (K).Start (I));
   function Neighbor (K : Graph_Kind; I : Natural; J : Positive) return Natural is
     (G (K).Adj (G (K).Start (I) + J - 1));

   function Nearest (K : Graph_Kind; X, Y, Max_R : Float) return Integer is
      R    : Graph renames G (K);
      Best : Integer := -1;
      BD   : Float := Max_R * Max_R;
      CX   : constant Integer := Integer (Float'Floor (X / GB));
      CY   : constant Integer := Integer (Float'Floor (Y / GB));
      Rings : constant Natural := Natural (Float'Ceiling (Max_R / GB));
   begin
      for Ring in 0 .. Rings loop
         for BY in CY - Ring .. CY + Ring loop
            for BX in CX - Ring .. CX + Ring loop
               if Integer'Max (abs (BX - CX), abs (BY - CY)) = Ring
                 and then BX >= 0 and then BY >= 0 and then BX < R.BW and then BY < R.BH
               then
                  declare
                     B : constant Natural := BY * R.BW + BX;
                  begin
                     for J in R.B_Start (B) .. R.B_Start (B + 1) - 1 loop
                        declare
                           I : constant Natural := R.B_List (J);
                           D : constant Float := (R.Xs (I) - X) ** 2 + (R.Ys (I) - Y) ** 2;
                        begin
                           if D < BD then
                              BD := D;
                              Best := I;
                           end if;
                        end;
                     end loop;
                  end;
               end if;
            end loop;
         end loop;
         exit when Best >= 0 and then Float (Ring) * GB > Sqrt (BD) + GB;
      end loop;
      return Best;
   end Nearest;

   function Undirected_Degree (K : Graph_Kind; I : Natural) return Natural is
     (G (K).UStart (I + 1) - G (K).UStart (I));

   function Undirected_Neighbor (K : Graph_Kind; I : Natural; J : Positive) return Natural is
     (G (K).UAdj (G (K).UStart (I) + J - 1));

   function Two_Way (A, B : Natural) return Boolean is
      R : Graph renames G (Car_Graph);
   begin
      for J in R.Start (B) .. R.Start (B + 1) - 1 loop
         if R.Adj (J) = A then
            return True;
         end if;
      end loop;
      return False;
   end Two_Way;

   --  A* working storage (car graph)
   AS_G     : Float_Array_Access;
   AS_Came  : Int_Array_Access;
   AS_Stamp : Int_Array_Access;
   AS_Done  : Int_Array_Access;
   Stamp    : Integer := 0;
   Heap_Max : constant := 40_000;
   Heap_F   : Float_Array (0 .. Heap_Max - 1);
   Heap_N   : Int_Array (0 .. Heap_Max - 1);

   procedure Find_Path (A, B : Integer; Path : out Int_Array; Len : out Natural) is
      R    : Graph renames G (Car_Graph);
      HN   : Natural := 0;
      Iter : Natural := 0;

      procedure Swap (I, J : Natural) is
         F : constant Float := Heap_F (I);
         N : constant Integer := Heap_N (I);
      begin
         Heap_F (I) := Heap_F (J); Heap_N (I) := Heap_N (J);
         Heap_F (J) := F; Heap_N (J) := N;
      end Swap;

      procedure Push (F : Float; N : Integer) is
         I : Natural := HN;
      begin
         if HN >= Heap_Max then
            return;
         end if;
         Heap_F (HN) := F; Heap_N (HN) := N; HN := HN + 1;
         while I > 0 and then Heap_F ((I - 1) / 2) > Heap_F (I) loop
            Swap (I, (I - 1) / 2);
            I := (I - 1) / 2;
         end loop;
      end Push;

      procedure Pop (N : out Integer) is
         I : Natural := 0;
      begin
         N := Heap_N (0);
         HN := HN - 1;
         Heap_F (0) := Heap_F (HN); Heap_N (0) := Heap_N (HN);
         loop
            declare
               L : constant Natural := 2 * I + 1;
               M : Natural := I;
            begin
               if L < HN and then Heap_F (L) < Heap_F (M) then
                  M := L;
               end if;
               if L + 1 < HN and then Heap_F (L + 1) < Heap_F (M) then
                  M := L + 1;
               end if;
               exit when M = I;
               Swap (I, M);
               I := M;
            end;
         end loop;
      end Pop;

      function Hcost (I : Natural) return Float is
        (Hypot (R.Xs (I) - R.Xs (B), R.Ys (I) - R.Ys (B)));
      Cur : Integer;
   begin
      Len := 0;
      Path := (others => 0);
      if A < 0 or else B < 0 then
         return;
      end if;
      Stamp := Stamp + 1;
      AS_Stamp (A) := Stamp; AS_G (A) := 0.0; AS_Came (A) := -1;
      Push (Hcost (A), A);
      while HN > 0 and then Iter < 8000 loop
         Iter := Iter + 1;
         Pop (Cur);
         if Cur = B then
            --  reconstruct (reverse), truncated to Path'Length nodes from the start
            declare
               Count : Natural := 0;
               C     : Integer := Cur;
            begin
               while C >= 0 loop
                  Count := Count + 1;
                  C := AS_Came (C);
               end loop;
               C := Cur;
               for K in reverse 1 .. Count loop
                  if K <= Path'Length then
                     Path (Path'First + K - 1) := C;
                  end if;
                  C := AS_Came (C);
               end loop;
               Len := Natural'Min (Count, Path'Length);
            end;
            return;
         end if;
         if AS_Done (Cur) /= Stamp then
            AS_Done (Cur) := Stamp;
            for J in R.UStart (Cur) .. R.UStart (Cur + 1) - 1 loop
               declare
                  Nb : constant Natural := R.UAdj (J);
                  NG : constant Float := AS_G (Cur) + Hypot (R.Xs (Nb) - R.Xs (Cur), R.Ys (Nb) - R.Ys (Cur));
               begin
                  if AS_Stamp (Nb) /= Stamp or else NG < AS_G (Nb) then
                     AS_Stamp (Nb) := Stamp;
                     AS_G (Nb) := NG;
                     AS_Came (Nb) := Cur;
                     Push (NG + Hcost (Nb), Nb);
                  end if;
               end;
            end loop;
         end if;
      end loop;
   end Find_Path;

   ------------------------------------------------------------------ street names
   type Name_Array is array (Natural range <>) of Unbounded_String;
   Names      : access Name_Array;
   NB         : constant Float := 40.0;
   NBW, NBH   : Natural := 0;
   Seg_Name, Seg_P, NB_Start, NB_List : Int_Array_Access;

   function Street_At (X, Y : Float) return String is
      Best : Integer := -1;
      BD   : Float := 30.0 * 30.0;
      CX   : constant Integer := Integer (Float'Floor (X / NB));
      CY   : constant Integer := Integer (Float'Floor (Y / NB));
   begin
      for BY in CY - 1 .. CY + 1 loop
         for BX in CX - 1 .. CX + 1 loop
            if BX >= 0 and then BY >= 0 and then BX < NBW and then BY < NBH then
               declare
                  B : constant Natural := BY * NBW + BX;
               begin
                  for J in NB_Start (B) .. NB_Start (B + 1) - 1 loop
                     declare
                        S  : constant Natural := NB_List (J);
                        P  : constant Natural := Seg_P (S);
                        AX : constant Float := Coords (P);
                        AY : constant Float := Coords (P + 1);
                        DX : constant Float := Coords (P + 2) - AX;
                        DY : constant Float := Coords (P + 3) - AY;
                        L  : constant Float := DX * DX + DY * DY;
                        T  : Float := (if L > 0.0 then ((X - AX) * DX + (Y - AY) * DY) / L else 0.0);
                        D  : Float;
                     begin
                        T := Clamp (T, 0.0, 1.0);
                        D := (X - AX - T * DX) ** 2 + (Y - AY - T * DY) ** 2;
                        if D < BD then
                           BD := D;
                           Best := Seg_Name (S);
                        end if;
                     end;
                  end loop;
               end;
            end if;
         end loop;
      end loop;
      return (if Best >= 0 then To_String (Names (Best)) else "");
   end Street_At;

   function District_At (X, Y : Float) return String is
      Best : Natural := Landmarks'First;
      BD   : Float := Float'Last;
   begin
      for I in Landmarks'Range loop
         declare
            D : constant Float := (Landmarks (I).X - X) ** 2 + (Landmarks (I).Y - Y) ** 2;
         begin
            if D < BD and then Element (Landmarks (I).Name, 1) /= '#' then
               BD := D;
               Best := I;
            end if;
         end;
      end loop;
      return To_String (Landmarks (Best).Name);
   end District_At;

   ------------------------------------------------------------------ collision grid
   type Byte_Grid is array (Natural range <>) of Unsigned_8;
   type Byte_Grid_Access is access Byte_Grid;
   Grid : Byte_Grid_Access;

   function Cell (X, Y : Float) return Natural is
   begin
      if X < 0.0 or else Y < 0.0 or else X >= Float (GW) or else Y >= Float (GH) then
         return 1;
      end if;
      return Natural (Grid (Natural (Float'Floor (Y)) * GW + Natural (Float'Floor (X))));
   end Cell;

   procedure Normal_At (X, Y : Float; Water_Solid : Boolean; NX, NY : out Float; Boat : Boolean := False) is
      SX, SY : Float := 0.0;
   begin
      for DY in -2 .. 2 loop
         for DX in -2 .. 2 loop
            declare
               C : constant Natural := Cell (X + Float (DX), Y + Float (DY));
            begin
               if (if Boat then C in 2 | 3 else C in 0 | 3 or else (C = 2 and then not Water_Solid)) then
                  SX := SX + Float (DX);
                  SY := SY + Float (DY);
               end if;
            end;
         end loop;
      end loop;
      declare
         L : constant Float := Hypot (SX, SY);
      begin
         if L > 0.0 then
            NX := SX / L; NY := SY / L;
         else
            NX := 0.0; NY := 0.0;
         end if;
      end;
   end Normal_At;

   function LOS (AX, AY, BX, BY : Float) return Boolean is
      D : constant Float := Hypot (BX - AX, BY - AY);
      T : Float := 0.0;
   begin
      if D < 0.01 then
         return True;
      end if;
      while T < D loop
         if Solid (AX + (BX - AX) * T / D, AY + (BY - AY) * T / D) then
            return False;
         end if;
         T := T + 0.5;
      end loop;
      return True;
   end LOS;

   procedure Path_Poly (Cr : Cairo_Context; P : Poly) is
   begin
      Move_To (Cr, Gdouble (Coords (P.First)), Gdouble (Coords (P.First + 1)));
      for K in 1 .. P.Count - 1 loop
         Line_To (Cr, Gdouble (Coords (P.First + 2 * K)), Gdouble (Coords (P.First + 2 * K + 1)));
      end loop;
      Close_Path (Cr);
   end Path_Poly;

   --  Rasterises buildings (1), water (2) and the outside of the boundary (1) with Cairo,
   --  in horizontal strips so the temporary surface stays small on a big map.
   procedure Build_Grid is
      Strip : constant Natural := 512;
   begin
      Grid := new Byte_Grid (0 .. GW * GH - 1);
      for Y0 in 0 .. (GH - 1) / Strip loop
         declare
            SY   : constant Natural := Y0 * Strip;
            SH   : constant Natural := Natural'Min (Strip, GH - SY);
            FY0  : constant Float := Float (SY) - 30.0;
            FY1  : constant Float := Float (SY + SH) + 30.0;
            Surf : constant Cairo_Surface := Create (Cairo_Format_ARGB32, Gint (GW), Gint (SH));
            Cr   : constant Cairo_Context := Create (Surf);
            function Near (B : BBox) return Boolean is (B.Y1 >= FY0 and then B.Y0 <= FY1);
         begin
            Set_Antialias (Cr, Cairo_Antialias_None);
            Translate (Cr, 0.0, Gdouble (-Float (SY)));
            Set_Source_Rgb (Cr, 0.0, 0.0, 0.0);
            Paint (Cr);
            Set_Fill_Rule (Cr, Cairo_Fill_Rule_Winding);
            Set_Source_Rgb (Cr, 0.0, 0.0, 1.0);
            for S of Water.all loop
               if Near (S.BB) then
                  Path_Poly (Cr, S.P);
               end if;
            end loop;
            Fill (Cr);
            Set_Source_Rgb (Cr, 0.0, 0.0, 0.0);
            for S of Holes.all loop
               if Near (S.BB) then
                  Path_Poly (Cr, S.P);
               end if;
            end loop;
            Fill (Cr);
            Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
            Set_Source_Rgb (Cr, 0.0, 0.5, 0.0);
            Set_Operator (Cr, Cairo_Operator_Add);     --  bridge over water: blue + green
            for R of Roads.all loop
               if R.Bridge and then R.Kind /= Rail and then Near (R.BB) then
                  Set_Line_Width (Cr, Gdouble (R.Width + 2.0));
                  Move_To (Cr, Gdouble (Coords (R.P.First)), Gdouble (Coords (R.P.First + 1)));
                  for K in 1 .. R.P.Count - 1 loop
                     Line_To (Cr, Gdouble (Coords (R.P.First + 2 * K)), Gdouble (Coords (R.P.First + 2 * K + 1)));
                  end loop;
                  Stroke (Cr);
               end if;
            end loop;
            Set_Operator (Cr, Cairo_Operator_Over);
            Set_Source_Rgb (Cr, 1.0, 0.0, 0.0);
            for B of Buildings.all loop
               if Near (B.BB) then
                  Path_Poly (Cr, B.P);
                  Fill (Cr);
               end if;
            end loop;
            if Boundary.Count > 2 then
               Set_Fill_Rule (Cr, Cairo_Fill_Rule_Even_Odd);
               Rectangle (Cr, -10.0, -10.0, Gdouble (W + 20.0), Gdouble (H + 20.0));
               Path_Poly (Cr, Boundary);
               Fill (Cr);
            end if;
            Cairo.Surface.Flush (Surf);
            declare
               Stride : constant Natural := Natural (Get_Stride (Surf));
               type Raw is array (0 .. Stride * SH - 1) of Unsigned_8;
               Data : Raw;
               for Data'Address use System.Address'(Get_Data_Generic (Surf));
               pragma Import (Ada, Data);
            begin
               for Y in 0 .. SH - 1 loop
                  for X in 0 .. GW - 1 loop
                     declare
                        O : constant Natural := Y * Stride + X * 4;   --  B G R A (little endian)
                     begin
                        Grid ((SY + Y) * GW + X) :=
                          (if Data (O + 2) > 110 then 1
                           elsif Data (O) > 110 then (if Data (O + 1) > 60 then 3 else 2)
                           else 0);
                     end;
                  end loop;
               end loop;
            end;
            Destroy (Cr);
            Cairo.Surface.Destroy (Surf);
         end;
      end loop;
   end Build_Grid;

   function In_Bounds (X, Y : Float) return Boolean is
      Inside : Boolean := False;
      N      : constant Natural := Boundary.Count;
      J      : Natural;
   begin
      if X < 0.0 or else Y < 0.0 or else X > W or else Y > H then
         return False;
      elsif N < 3 then
         return True;
      end if;
      J := N - 1;
      for I in 0 .. N - 1 loop
         declare
            XI : constant Float := Coords (Boundary.First + 2 * I);
            YI : constant Float := Coords (Boundary.First + 2 * I + 1);
            XJ : constant Float := Coords (Boundary.First + 2 * J);
            YJ : constant Float := Coords (Boundary.First + 2 * J + 1);
         begin
            if (YI > Y) /= (YJ > Y) and then X < (XJ - XI) * (Y - YI) / (YJ - YI) + XI then
               Inside := not Inside;
            end if;
         end;
         J := I;
      end loop;
      return Inside;
   end In_Bounds;

   ------------------------------------------------------------------ load
   function Less (A, B : Building) return Boolean is (A.H < B.H);
   procedure Sort_Buildings is new Ada.Containers.Generic_Array_Sort
     (Natural, Building, Building_Array, Less);

   --  releases a previously loaded map (switching worlds at the title screen)
   ------------------------------------------------------------------ city settings
   type Pair is record
      K, V : Unbounded_String;
   end record;
   type Pair_Array is array (Positive range <>) of Pair;
   Metas : access Pair_Array;

   function Meta (Key, Default : String) return String is
   begin
      if Metas /= null then
         for P of Metas.all loop
            if P.K = Key then
               return To_String (P.V);
            end if;
         end loop;
      end if;
      return Default;
   end Meta;

   function Meta_Item (Key, Default : String; I : Positive) return String is
      S     : constant String := Meta (Key, Default);
      N     : Positive := 1;
      First : Natural := S'First;
   begin
      for J in S'Range loop
         if S (J) = ';' then
            if N = I then
               return S (First .. J - 1);
            end if;
            N := N + 1;
            First := J + 1;
         end if;
      end loop;
      return (if N = I then S (First .. S'Last) else "");
   end Meta_Item;

   procedure Free_All is
      procedure Free is new Ada.Unchecked_Deallocation (Float_Array, Float_Array_Access);
      procedure Free is new Ada.Unchecked_Deallocation (Int_Array, Int_Array_Access);
      procedure Free is new Ada.Unchecked_Deallocation (Byte_Grid, Byte_Grid_Access);
      procedure Free is new Ada.Unchecked_Deallocation (Road_Array, Road_Access);
      procedure Free is new Ada.Unchecked_Deallocation (Shape_Array, Shape_Access);
      procedure Free is new Ada.Unchecked_Deallocation (Building_Array, Building_Access);
      procedure Free is new Ada.Unchecked_Deallocation (Landmark_Array, Landmark_Access);
   begin
      Free (Grid); Free (Coords);
      Free (Roads); Free (Areas); Free (Parks); Free (Water); Free (Holes);
      Free (Buildings); Free (Landmarks);
      for K in Graph_Kind loop
         Free (G (K).Xs); Free (G (K).Ys); Free (G (K).Start); Free (G (K).Adj);
         Free (G (K).UStart); Free (G (K).UAdj); Free (G (K).B_Start); Free (G (K).B_List);
      end loop;
      Free (AS_G); Free (AS_Came); Free (AS_Stamp); Free (AS_Done);
      Free (Seg_Name); Free (Seg_P); Free (NB_Start); Free (NB_List);
      Names := null;   --  small; left to the allocator
   end Free_All;

   procedure Load (Path : String) is
      use Ada.Streams.Stream_IO;
      Version : Integer;
      F    : File_Type;
      Size : constant Stream_Element_Offset := Stream_Element_Offset (Ada.Directories.Size (Path));
      Last : Stream_Element_Offset;
   begin
      Free_All;
      Buf := new Stream_Element_Array (1 .. Size);
      Open (F, In_File, Path);
      Read (F, Buf.all, Last);
      Close (F);
      Pos := 1;
      if Character'Val (Buf (1)) /= 'P' or else Character'Val (Buf (4)) /= 'E' then
         raise Program_Error with "not a PAVE map file: " & Path;
      end if;
      Pos := 5;
      Version := RI;
      W := RF; H := RF;
      GW := Natural (Float'Ceiling (W)); GH := Natural (Float'Ceiling (H));
      Tmp := new Float_Array (0 .. 1_000_000);
      Tmp_Count := 0;

      declare
         N : constant Natural := RI;
      begin
         Roads := new Road_Array (0 .. N - 1);
         for R of Roads.all loop
            declare
               K : constant Integer := RI;
            begin
               R.Kind := (case K is when 0 => Car_Road, when 1 => Ped_Area, when 3 => Rail, when others => Footway);
            end;
            R.Width := RF;
            R.Bridge := RI /= 0;
            R.P := Read_Poly;
            R.BB := Box_Of (R.P);
         end loop;
      end;
      Areas := Read_Shapes;
      Parks := Read_Shapes;
      Water := Read_Shapes;
      Holes := Read_Shapes;
      --  water one way round, islands the other: filled with the winding rule, overlapping
      --  water (sea + harbour basin) stays water and islands still cut holes
      for S of Water.all loop
         Orient (S.P, Clockwise => True);
      end loop;
      for S of Holes.all loop
         Orient (S.P, Clockwise => False);
      end loop;
      declare
         N : constant Natural := RI;
      begin
         Buildings := new Building_Array (0 .. N - 1);
         for I in Buildings'Range loop
            declare
               B : Building renames Buildings (I);
               A : Float := 0.0;
               R : constant Float := Hash (Float (I + 1));
            begin
               B.H := RF;
               B.Special := RI /= 0;
               B.P := Read_Poly;
               B.BB := Box_Of (B.P);
               for K in 0 .. B.P.Count - 1 loop
                  declare
                     J : constant Natural := B.P.First + 2 * K;
                     Q : constant Natural := B.P.First + 2 * ((K + 1) mod B.P.Count);
                  begin
                     A := A + Tmp (J) * Tmp (Q + 1) - Tmp (Q) * Tmp (J + 1);
                  end;
               end loop;
               B.CW := A > 0.0;
               if B.Special then
                  B.Roof := HSL (40.0, 18.0 + R * 10.0, 66.0 + R * 8.0);
               elsif R < 0.7 then
                  B.Roof := HSL (205.0 + R * 20.0, 8.0 + R * 8.0, 44.0 + R * 14.0);   --  zinc
               else
                  B.Roof := HSL (12.0 + R * 14.0, 30.0 + R * 15.0, 42.0 + R * 10.0);  --  terracotta
               end if;
            end;
         end loop;
         Sort_Buildings (Buildings.all);
      end;
      Read_Graph (Car_Graph);
      Read_Graph (Ped_Graph);
      --  street names: segments bucketed on a 40 m grid
      declare
         N     : constant Natural := RI;
         Polys : array (0 .. N - 1) of Poly;
         NSeg  : Natural := 0;
      begin
         Names := new Name_Array (0 .. Integer'Max (N, 1) - 1);
         for I in 0 .. N - 1 loop
            Names (I) := RS;
            Polys (I) := Read_Poly;
            NSeg := NSeg + Natural'Max (0, Polys (I).Count - 1);
         end loop;
         Seg_Name := new Int_Array (0 .. Integer'Max (NSeg, 1) - 1);
         Seg_P := new Int_Array (0 .. Integer'Max (NSeg, 1) - 1);
         NBW := Natural (Float'Ceiling (W / NB)); NBH := Natural (Float'Ceiling (H / NB));
         declare
            S   : Natural := 0;
            Cnt : Int_Array_Access := new Int_Array'(0 .. NBW * NBH => 0);
            BOf : Int_Array_Access := new Int_Array (0 .. Integer'Max (NSeg, 1) - 1);
         begin
            for I in 0 .. N - 1 loop
               for K in 0 .. Polys (I).Count - 2 loop
                  declare
                     P  : constant Natural := Polys (I).First + 2 * K;
                     MX : constant Float := (Tmp (P) + Tmp (P + 2)) / 2.0;
                     MY : constant Float := (Tmp (P + 1) + Tmp (P + 3)) / 2.0;
                     BX : constant Integer := Integer'Max (0, Integer'Min (NBW - 1, Integer (Float'Floor (MX / NB))));
                     BY : constant Integer := Integer'Max (0, Integer'Min (NBH - 1, Integer (Float'Floor (MY / NB))));
                  begin
                     Seg_Name (S) := I; Seg_P (S) := P;
                     BOf (S) := BY * NBW + BX;
                     Cnt (BOf (S) + 1) := Cnt (BOf (S) + 1) + 1;
                     S := S + 1;
                  end;
               end loop;
            end loop;
            for I in 1 .. Cnt'Last loop
               Cnt (I) := Cnt (I) + Cnt (I - 1);
            end loop;
            NB_Start := new Int_Array'(Cnt.all);
            NB_List := new Int_Array (0 .. Integer'Max (S, 1) - 1);
            for J in 0 .. S - 1 loop     --  Cnt becomes the fill cursor
               NB_List (Cnt (BOf (J))) := J;
               Cnt (BOf (J)) := Cnt (BOf (J)) + 1;
            end loop;
            pragma Unreferenced (BOf);
         end;
      end;
      declare
         N : constant Natural := RI;
      begin
         Landmarks := new Landmark_Array (0 .. N - 1);
         for L of Landmarks.all loop
            L.Name := RS;
            L.X := RF;
            L.Y := RF;
         end loop;
      end;
      Boundary := (if Version >= 2 then Read_Poly else (0, 0));
      Metas := null;
      if Version >= 3 then
         declare
            N : constant Natural := RI;
         begin
            Metas := new Pair_Array (1 .. N);
            for P of Metas.all loop
               P.K := RS;
               P.V := RS;
            end loop;
         end;
      end if;
      Coords := new Float_Array'(Tmp (0 .. Tmp_Count - 1));
      Tmp := null;
      Buf := null;

      declare
         N : constant Natural := G (Car_Graph).N;
      begin
         AS_G := new Float_Array (0 .. N - 1);
         AS_Came := new Int_Array (0 .. N - 1);
         AS_Stamp := new Int_Array'(0 .. N - 1 => 0);
         AS_Done := new Int_Array'(0 .. N - 1 => 0);
      end;
      Build_Grid;
   end Load;

end World;
