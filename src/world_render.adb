-- ***************************************************************************
--                      PAVÉ - World_Render
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

with Glib;  use Glib;
with Util;  use Util;
with World; use World;
with Gfx;   use Gfx;
with Cairo.Image_Surface; use Cairo.Image_Surface;
with Cairo.Surface;
with Cairo.Pattern;
with Ada.Containers.Vectors;
with Ada.Unchecked_Deallocation;

package body World_Render is

   TILE : constant Float := 100.0;
   PPM  : constant Float := 5.0;
   TPX  : constant Gint := 500;
   Max_Cached : constant := 90;

   package Index_Vectors is new Ada.Containers.Vectors (Natural, Natural);
   use Index_Vectors;

   type Bucket is record
      Roads, Areas, Parks, Water, Holes, Bld : Vector;
   end record;
   type Bucket_Array is array (Natural range <>) of Bucket;
   type Bucket_Access is access Bucket_Array;

   Tiles_X, Tiles_Y : Natural := 0;
   TB               : Bucket_Access;

   type Tile_Slot is record
      Surf : Cairo_Surface := Null_Surface;
      Used : Natural := 0;
   end record;
   type Tile_Array is array (Natural range <>) of Tile_Slot;
   Cache   : access Tile_Array;
   N_Cache : Natural := 0;
   Clock   : Natural := 0;

   --  building buckets (64 m), CSR
   BB_Size  : constant Float := 64.0;
   BBW, BBH : Natural := 0;
   B_Start, B_List : Int_Array_Access;
   B_Stamp  : Int_Array_Access;
   Frame    : Integer := 0;

   Wall : array (Boolean, 0 .. 15) of RGB;

   C_Ground   : constant RGB := Hex ("#8e8a80");
   C_Park     : constant RGB := Hex ("#5f8a45");
   C_Park_E   : constant RGB := Hex ("#4f7639");
   C_Water    : constant RGB := Hex ("#3f6f8f");
   C_Square   : constant RGB := Hex ("#b3aa96");
   C_Sidewalk : constant RGB := Hex ("#a8a194");
   C_Asphalt  : constant RGB := Hex ("#4a4a4e");
   C_Footway  : constant RGB := Hex ("#bdb39d");
   C_Bridge   : constant RGB := Hex ("#9b8f7a");
   C_Quay     : constant RGB := Hex ("#a59b86");
   C_Kerb     : constant RGB := Hex ("#6f6b63");
   C_Ballast  : constant RGB := Hex ("#7d7468");
   C_Outside  : constant RGB := Hex ("#2b3a44");
   C_Window   : constant RGB := Hex ("#2f3a46");
   C_Shop     : constant RGB := Hex ("#3b3530");
   C_Brick    : constant RGB := Hex ("#8a5443");
   C_Pot      : constant RGB := Hex ("#c07a4e");
   Awnings    : constant array (0 .. 4) of RGB :=
     (Hex ("#a3343a"), Hex ("#2f6b4a"), Hex ("#2d4a7a"), Hex ("#7a2a4e"), Hex ("#b0763a"));

   function Clampi (V, Lo, Hi : Integer) return Integer is (Integer'Max (Lo, Integer'Min (Hi, V)));
   function Fl (V : Float) return Integer is (Integer (Float'Floor (V)));

   generic
      with procedure Add (B : in out Bucket; I : Natural);
   procedure Bucketize (Box : BBox; Margin : Float; I : Natural);
   procedure Bucketize (Box : BBox; Margin : Float; I : Natural) is
   begin
      for TY in Clampi (Fl ((Box.Y0 - Margin) / TILE), 0, Tiles_Y - 1) .. Clampi (Fl ((Box.Y1 + Margin) / TILE), 0, Tiles_Y - 1) loop
         for TX in Clampi (Fl ((Box.X0 - Margin) / TILE), 0, Tiles_X - 1) .. Clampi (Fl ((Box.X1 + Margin) / TILE), 0, Tiles_X - 1) loop
            Add (TB (TY * Tiles_X + TX), I);
         end loop;
      end loop;
   end Bucketize;

   procedure Add_Road (B : in out Bucket; I : Natural) is begin B.Roads.Append (I); end Add_Road;
   procedure Add_Area (B : in out Bucket; I : Natural) is begin B.Areas.Append (I); end Add_Area;
   procedure Add_Park (B : in out Bucket; I : Natural) is begin B.Parks.Append (I); end Add_Park;
   procedure Add_Water (B : in out Bucket; I : Natural) is begin B.Water.Append (I); end Add_Water;
   procedure Add_Hole (B : in out Bucket; I : Natural) is begin B.Holes.Append (I); end Add_Hole;
   procedure Add_Bld (B : in out Bucket; I : Natural) is begin B.Bld.Append (I); end Add_Bld;
   procedure B_Road is new Bucketize (Add_Road);
   procedure B_Area is new Bucketize (Add_Area);
   procedure B_Park is new Bucketize (Add_Park);
   procedure B_Water is new Bucketize (Add_Water);
   procedure B_Hole is new Bucketize (Add_Hole);
   procedure B_Bld is new Bucketize (Add_Bld);


   ------------------------------------------------------------------ street furniture
   --  width of the car road nearest to (X, Y) among a tile's roads (0 if none near)
   function Road_Width_At (B : Bucket; X, Y : Float) return Float is
      C      : Float_Array renames Coords.all;
      Best   : Float := 6.0;
      Best_W : Float := 0.0;
   begin
      for I of B.Roads loop
         declare
            R : Road renames Roads (I);
         begin
            if R.Kind = Car_Road and then X >= R.BB.X0 - 6.0 and then X <= R.BB.X1 + 6.0
              and then Y >= R.BB.Y0 - 6.0 and then Y <= R.BB.Y1 + 6.0
            then
               for J in 0 .. R.P.Count - 2 loop
                  declare
                     AX : constant Float := C (R.P.First + 2 * J);
                     AY : constant Float := C (R.P.First + 2 * J + 1);
                     DX : constant Float := C (R.P.First + 2 * J + 2) - AX;
                     DY : constant Float := C (R.P.First + 2 * J + 3) - AY;
                     L2 : constant Float := Float'Max (DX * DX + DY * DY, 0.0001);
                     T  : constant Float := Clamp (((X - AX) * DX + (Y - AY) * DY) / L2, 0.0, 1.0);
                     D  : constant Float := Hypot (AX + DX * T - X, AY + DY * T - Y);
                  begin
                     if D < Best then
                        Best := D; Best_W := R.Width;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;
      return Best_W;
   end Road_Width_At;

   --  True if (X, Y) is on (or within Margin of) the asphalt of any car road in the tile
   function On_Asphalt (B : Bucket; X, Y, Margin : Float) return Boolean is
      C : Float_Array renames Coords.all;
   begin
      for I of B.Roads loop
         declare
            R : Road renames Roads (I);
            Reach : constant Float := R.Width / 2.0 + Margin;
         begin
            if R.Kind = Car_Road and then X >= R.BB.X0 - Reach and then X <= R.BB.X1 + Reach
              and then Y >= R.BB.Y0 - Reach and then Y <= R.BB.Y1 + Reach
            then
               for J in 0 .. R.P.Count - 2 loop
                  declare
                     AX : constant Float := C (R.P.First + 2 * J);
                     AY : constant Float := C (R.P.First + 2 * J + 1);
                     DX : constant Float := C (R.P.First + 2 * J + 2) - AX;
                     DY : constant Float := C (R.P.First + 2 * J + 3) - AY;
                     L2 : constant Float := Float'Max (DX * DX + DY * DY, 0.0001);
                     T  : constant Float := Clamp (((X - AX) * DX + (Y - AY) * DY) / L2, 0.0, 1.0);
                  begin
                     if Hypot (AX + DX * T - X, AY + DY * T - Y) < Reach then
                        return True;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;
      return False;
   end On_Asphalt;

   --  zebra crossings on every arm of a junction (car-graph node with 3+ neighbours)
   procedure Draw_Crossings (Cr : Cairo_Context; B : Bucket; OX, OY : Float) is
   begin
      Color (Cr, 0.93, 0.93, 0.9, 0.8);
      for N in 0 .. Node_Count (Car_Graph) - 1 loop
         declare
            X : constant Float := NX (Car_Graph, N);
            Y : constant Float := NY (Car_Graph, N);
         begin
            if X > OX - 25.0 and then X < OX + TILE + 25.0 and then Y > OY - 25.0 and then Y < OY + TILE + 25.0
              and then Undirected_Degree (Car_Graph, N) >= 3
            then
               declare
                  Seen  : Int_Array (1 .. 12) := (others => -1);
                  N_Arm : Natural := 0;
                  Wide  : Float := 0.0;
               begin
                  --  junction size = widest road meeting here
                  for J in 1 .. Natural'Min (Undirected_Degree (Car_Graph, N), 12) loop
                     declare
                        M  : constant Natural := Undirected_Neighbor (Car_Graph, N, J);
                        DX : constant Float := NX (Car_Graph, M) - X;
                        DY : constant Float := NY (Car_Graph, M) - Y;
                        L  : constant Float := Float'Max (Hypot (DX, DY), 0.01);
                     begin
                        Wide := Float'Max (Wide, Road_Width_At (B, X + DX / L * 4.0, Y + DY / L * 4.0));
                     end;
                  end loop;
                  for J in 1 .. Natural'Min (Undirected_Degree (Car_Graph, N), 12) loop
                     declare
                        M  : constant Natural := Undirected_Neighbor (Car_Graph, N, J);
                        DX : constant Float := NX (Car_Graph, M) - X;
                        DY : constant Float := NY (Car_Graph, M) - Y;
                        L  : constant Float := Float'Max (Hypot (DX, DY), 0.01);
                        UX : constant Float := DX / L;
                        UY : constant Float := DY / L;
                        Dup : Boolean := False;
                     begin
                        for K in 1 .. N_Arm loop
                           Dup := Dup or else Seen (K) = M;
                        end loop;
                        if not Dup and then Wide > 0.0 then
                           N_Arm := N_Arm + 1;
                           Seen (N_Arm) := M;
                           declare
                              D  : constant Float := Wide / 2.0 + 2.5;
                              CX : constant Float := X + UX * D;
                              CY : constant Float := Y + UY * D;
                              RW : constant Float := Road_Width_At (B, CX, CY);
                              HL : constant Float := RW / 2.0 - 0.6;
                           begin
                              if L > D + 6.0 and then RW >= 5.0 then
                                 --  stripes: a dashed line across the road, as thick as the crossing is deep
                                 Width (Cr, 2.6);
                                 Set_Dash (Cr, (0.55, 0.55), 0.0);
                                 Move (Cr, CX - UY * HL, CY + UX * HL);
                                 Line (Cr, CX + UY * HL, CY - UX * HL);
                                 Stroke (Cr);
                              end if;
                           end;
                        end if;
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;
      Set_Dash (Cr, (1 .. 0 => 0.0), 0.0);
   end Draw_Crossings;

   --  plane trees along both pavements of the wide boulevards
   procedure Draw_Trees (Cr : Cairo_Context; B : Bucket) is
      C : Float_Array renames Coords.all;
      Spacing : constant Float := 9.0;

      procedure Tree (X, Y, Seed : Float) is
         R : constant Float := 2.0 + Hash (Seed) * 0.8;
      begin
         Color (Cr, 0.0, 0.0, 0.0, 0.22);
         Fill_Circle (Cr, X + 0.9, Y + 1.2, R);
         Color (Cr, HSL (95.0 + Hash (Seed * 1.7) * 25.0, 35.0, 27.0 + Hash (Seed * 2.3) * 6.0));
         Fill_Circle (Cr, X, Y, R);
         Color (Cr, 1.0, 1.0, 0.8, 0.10);
         Fill_Circle (Cr, X - R * 0.25, Y - R * 0.3, R * 0.6);
         Color (Cr, 0.0, 0.0, 0.0, 0.12);
         Width (Cr, 0.25);
         Circle (Cr, X, Y, R);
         Stroke (Cr);
      end Tree;
   begin
      for I of B.Roads loop
         declare
            R    : Road renames Roads (I);
            Next : Float := Spacing / 2.0;   --  distance of the next tree along the road
            Run  : Float := 0.0;
         begin
            if R.Kind = Car_Road and then R.Width >= 12.0 and then not R.Bridge then
               for J in 0 .. R.P.Count - 2 loop
                  declare
                     AX : constant Float := C (R.P.First + 2 * J);
                     AY : constant Float := C (R.P.First + 2 * J + 1);
                     DX : constant Float := C (R.P.First + 2 * J + 2) - AX;
                     DY : constant Float := C (R.P.First + 2 * J + 3) - AY;
                     L  : constant Float := Hypot (DX, DY);
                  begin
                     if L > 0.01 then
                        while Next <= Run + L loop
                           declare
                              T   : constant Float := (Next - Run) / L;
                              Off : constant Float := R.Width / 2.0 + 1.6;
                           begin
                              for Side in -1 .. 1 loop
                                 if Side /= 0 then
                                    declare
                                       TX : constant Float := AX + DX * T - DY / L * Off * Float (Side);
                                       TY : constant Float := AY + DY * T + DX / L * Off * Float (Side);
                                       Jn : constant Integer := Nearest (Car_Graph, TX, TY, 11.0);
                                    begin
                                       if World.Cell (TX, TY) = 0          --  plain ground only
                                         and then (Jn < 0 or else Undirected_Degree (Car_Graph, Jn) < 3)
                                         and then not On_Asphalt (B, TX, TY, 0.6)
                                       then
                                          Tree (TX, TY, Float (I) * 3.3 + Next * 0.37 + Float (Side));
                                       end if;
                                    end;
                                 end if;
                              end loop;
                           end;
                           Next := Next + Spacing;
                        end loop;
                        Run := Run + L;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;
   end Draw_Trees;

   --  ballast bed, sleepers and two rails
   procedure Draw_Rails (Cr : Cairo_Context; B : Bucket) is
      Any : Boolean := False;
   begin
      for I of B.Roads loop
         if Roads (I).Kind = Rail then
            Line_Path (Cr, Roads (I).P);
            Any := True;
         end if;
      end loop;
      if not Any then
         return;
      end if;
      Color (Cr, C_Ballast);
      Width (Cr, 3.4);
      Stroke_Preserve (Cr);
      Color (Cr, 0.32, 0.26, 0.2, 0.8);           --  sleepers
      Width (Cr, 2.4);
      Set_Dash (Cr, (0.25, 0.45), 0.0);
      Stroke_Preserve (Cr);
      Set_Dash (Cr, (1 .. 0 => 0.0), 0.0);
      Color (Cr, 0.62, 0.62, 0.64);                --  rails: a wide line with the middle cut out
      Width (Cr, 1.6);
      Stroke_Preserve (Cr);
      Color (Cr, 0.32, 0.26, 0.2);
      Width (Cr, 1.25);
      Stroke (Cr);
   end Draw_Rails;

   --  everything outside the Peripherique: dark, unreachable banlieue
   procedure Draw_Outside (Cr : Cairo_Context; X, Y, Size : Float) is
   begin
      if Boundary.Count < 3 then
         return;
      end if;
      Set_Fill_Rule (Cr, Cairo_Fill_Rule_Even_Odd);
      Rect (Cr, X - 1.0, Y - 1.0, Size + 2.0, Size + 2.0);
      Poly_Path (Cr, Boundary);
      Color (Cr, C_Outside);
      Fill (Cr);
      Set_Fill_Rule (Cr, Cairo_Fill_Rule_Winding);
   end Draw_Outside;

   ------------------------------------------------------------------ tiles
   function Render_Tile (TX, TY : Natural) return Cairo_Surface is
      S  : constant Cairo_Surface := Create (Cairo_Format_ARGB32, TPX, TPX);
      Cr : constant Cairo_Context := Create (S);
      B  : Bucket renames TB (TY * Tiles_X + TX);
      OX : constant Float := Float (TX) * TILE;
      OY : constant Float := Float (TY) * TILE;
   begin
      Gfx.Scale (Cr, PPM);
      Gfx.Translate (Cr, -OX, -OY);
      Color (Cr, C_Ground);
      Fill_Rect (Cr, OX, OY, TILE, TILE);
      for I in 0 .. 259 loop
         declare
            R : constant Float := Hash (Float (TX * 977 + TY * 131 + I));
         begin
            if R > 0.5 then
               Color (Cr, 1.0, 1.0, 0.94, 0.04);
            else
               Color (Cr, 0.0, 0.0, 0.0, 0.04);
            end if;
            Fill_Rect (Cr, OX + Hash (Float (I) * 3.1 + Float (TX)) * TILE,
                       OY + Hash (Float (I) * 7.7 + Float (TY)) * TILE, 1.5 + R * 3.0, 1.5 + R * 2.0);
         end;
      end loop;
      Color (Cr, C_Square);
      for I of B.Areas loop
         Poly_Path (Cr, Areas (I).P);
      end loop;
      Fill (Cr);
      if not B.Parks.Is_Empty then
         for I of B.Parks loop
            Poly_Path (Cr, Parks (I).P);
         end loop;
         Color (Cr, C_Park);
         Fill_Preserve (Cr);
         Color (Cr, C_Park_E);
         Width (Cr, 0.6);
         Stroke_Preserve (Cr);
         Save (Cr);
         Clip (Cr);
         for I in 0 .. 159 loop
            Color (Cr, 30.0 / 255.0, (70.0 + Hash (Float (I)) * 40.0) / 255.0, 25.0 / 255.0, 0.55);
            Fill_Circle (Cr, OX + Hash (Float (I) * 1.37 + Float (TX * 9)) * TILE,
                         OY + Hash (Float (I) * 2.71 + Float (TY * 5)) * TILE,
                         1.5 + Hash (Float (I) * 5.3) * 2.2);
         end loop;
         Restore (Cr);
         New_Path (Cr);
      end if;
      if not B.Water.Is_Empty then
         Set_Fill_Rule (Cr, Cairo_Fill_Rule_Winding);
         for I of B.Water loop
            Poly_Path (Cr, World.Water (I).P);
         end loop;
         for I of B.Holes loop
            Poly_Path (Cr, World.Holes (I).P);
         end loop;
         Color (Cr, C_Water);
         Fill_Preserve (Cr);
         Color (Cr, C_Quay);
         Width (Cr, 2.5);
         Stroke_Preserve (Cr);
         Save (Cr);
         Clip (Cr);
         Color (Cr, 1.0, 1.0, 1.0, 0.07);
         Width (Cr, 0.4);
         for I in 0 .. 69 loop
            declare
               X : constant Float := OX + Hash (Float (I) * 4.1 + Float (TX)) * TILE;
               Y : constant Float := OY + Hash (Float (I) * 6.3 + Float (TY)) * TILE;
            begin
               Move (Cr, X, Y);
               Line (Cr, X + 3.0 + Hash (Float (I)) * 5.0, Y + 0.4);
            end;
         end loop;
         Stroke (Cr);
         Restore (Cr);
         New_Path (Cr);
         Set_Fill_Rule (Cr, Cairo_Fill_Rule_Winding);
      end if;
      Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
      Set_Line_Join (Cr, Cairo_Line_Join_Round);
      Draw_Rails (Cr, B);
      for I of B.Roads loop
         declare
            R : Road renames Roads (I);
         begin
            if R.Kind in Ped_Area | Footway then
               Color (Cr, (if R.Bridge then C_Bridge elsif R.Kind = Ped_Area then C_Square else C_Footway));
               Width (Cr, R.Width);
               Line_Path (Cr, R.P);
               Stroke (Cr);
            end if;
         end;
      end loop;
      for I of B.Roads loop
         declare
            R : Road renames Roads (I);
         begin
            if R.Kind = Car_Road then
               Color (Cr, (if R.Bridge then C_Bridge else C_Sidewalk));
               Width (Cr, R.Width + (if R.Bridge then 3.0 else 4.5));
               Line_Path (Cr, R.P);
               Stroke (Cr);
            end if;
         end;
      end loop;
      Color (Cr, C_Kerb);
      for I of B.Roads loop
         if Roads (I).Kind = Car_Road and then not Roads (I).Bridge then
            Width (Cr, Roads (I).Width + 0.7);
            Line_Path (Cr, Roads (I).P);
            Stroke (Cr);
         end if;
      end loop;
      Color (Cr, C_Asphalt);
      for I of B.Roads loop
         if Roads (I).Kind = Car_Road then
            Width (Cr, Roads (I).Width);
            Line_Path (Cr, Roads (I).P);
            Stroke (Cr);
         end if;
      end loop;
      Color (Cr, 0.92, 0.92, 0.88, 0.75);
      Width (Cr, 0.25);
      Set_Dash (Cr, (3.0, 4.0), 0.0);
      for I of B.Roads loop
         if Roads (I).Kind = Car_Road and then Roads (I).Width >= 10.0 then
            Line_Path (Cr, Roads (I).P);
            Stroke (Cr);
         end if;
      end loop;
      Set_Dash (Cr, (1 .. 0 => 0.0), 0.0);
      Set_Line_Cap (Cr, Cairo_Line_Cap_Butt);
      Draw_Crossings (Cr, B, OX, OY);
      Draw_Trees (Cr, B);
      Draw_Outside (Cr, OX, OY, TILE);
      --  building ground shadows
      Color (Cr, 0.0, 0.0, 0.0, 0.28);
      Gfx.Translate (Cr, 1.6, 2.2);
      for I of B.Bld loop
         Poly_Path (Cr, Buildings (I).P);
      end loop;
      Fill (Cr);
      Destroy (Cr);
      return S;
   end Render_Tile;

   function Get_Tile (TX, TY : Natural; Allow : Boolean) return Cairo_Surface is
      K : constant Natural := TY * Tiles_X + TX;
   begin
      Clock := Clock + 1;
      if Cache (K).Surf /= Null_Surface then
         Cache (K).Used := Clock;
         return Cache (K).Surf;
      end if;
      if not Allow then
         return Null_Surface;
      end if;
      if N_Cache >= Max_Cached then
         --  evict least recently used
         declare
            Old : Natural := 0;
            OU  : Natural := Natural'Last;
         begin
            for J in Cache'Range loop
               if Cache (J).Surf /= Null_Surface and then Cache (J).Used < OU then
                  OU := Cache (J).Used;
                  Old := J;
               end if;
            end loop;
            Cairo.Surface.Destroy (Cache (Old).Surf);
            Cache (Old).Surf := Null_Surface;
            N_Cache := N_Cache - 1;
         end;
      end if;
      Cache (K).Surf := Render_Tile (TX, TY);
      Cache (K).Used := Clock;
      N_Cache := N_Cache + 1;
      return Cache (K).Surf;
   end Get_Tile;

   procedure Draw_Ground (Cr : Cairo_Context; X0, Y0, X1, Y1 : Float; Budget : Natural := 4) is
      Rendered : Natural := 0;
   begin
      Color (Cr, C_Outside);
      Fill_Rect (Cr, X0 - 5.0, Y0 - 5.0, X1 - X0 + 10.0, Y1 - Y0 + 10.0);
      for TY in Clampi (Fl (Y0 / TILE), 0, Tiles_Y - 1) .. Clampi (Fl (Y1 / TILE), 0, Tiles_Y - 1) loop
         for TX in Clampi (Fl (X0 / TILE), 0, Tiles_X - 1) .. Clampi (Fl (X1 / TILE), 0, Tiles_X - 1) loop
            declare
               S : Cairo_Surface := Get_Tile (TX, TY, False);
            begin
               if S = Null_Surface and then Rendered < Budget then
                  S := Get_Tile (TX, TY, True);
                  Rendered := Rendered + 1;
               end if;
               if S /= Null_Surface then
                  Save (Cr);
                  Gfx.Translate (Cr, Float (TX) * TILE, Float (TY) * TILE);
                  Gfx.Scale (Cr, 1.0 / PPM);
                  Set_Source_Surface (Cr, S, 0.0, 0.0);
                  Cairo.Pattern.Set_Extend (Get_Source (Cr), Cairo.Pattern.Cairo_Extend_Pad);
                  Rect (Cr, 0.0, 0.0, Float (TPX) + 0.3, Float (TPX) + 0.3);
                  Fill (Cr);
                  Restore (Cr);
               end if;
            end;
         end loop;
      end loop;
   end Draw_Ground;

   ------------------------------------------------------------------ building details
   --  windows on every floor of the camera-facing walls, shopfronts with awnings on
   --  the ground floor. Points on a wall are found by interpolating along the edge
   --  and up the (perspective-correct) height.
   procedure Facade (Cr : Cairo_Context; B : Building; Id : Natural; Roof : Float_Array;
                     Cnt : Natural; Cam_X, Cam_Y, Cam_H, Zoom : Float)
   is
      C      : Float_Array renames Coords.all;
      P      : constant Natural := B.P.First;
      Floors : constant Positive := Positive (Clamp (Float'Rounding (B.H / 3.3), 1.0, 10.0));
      KH     : constant Float := B.H / Float'Max (Cam_H - B.H, 20.0);
      Shops  : constant Boolean := not B.Special and then Floors >= 3 and then Hash (Float (Id) * 0.731) > 0.3;
      Awning : constant RGB := Awnings (Natural (Float'Floor (Hash (Float (Id) * 1.913) * 4.99)));
      G      : array (0 .. 20) of Float;   --  height fraction -> fraction of the roof offset

      function GZ (Z : Float) return Float is
         H : constant Float := Z * B.H;
      begin
         return (H / Float'Max (Cam_H - H, 20.0)) / Float'Max (KH, 0.0001);
      end GZ;

      type Pass_Kind is (Windows, Shopfronts, Awnings_Pass);
   begin
      for I in G'Range loop
         G (I) := GZ (Float (I) / 20.0);
      end loop;
      for Pass in Pass_Kind loop
         exit when Pass /= Windows and then not Shops;
         declare
            Any : Boolean := False;
         begin
            for J in 0 .. Cnt - 1 loop
               declare
                  Q  : constant Natural := (J + 1) mod Cnt;
                  AX : constant Float := C (P + 2 * J);
                  AY : constant Float := C (P + 2 * J + 1);
                  BX : constant Float := C (P + 2 * Q);
                  BY : constant Float := C (P + 2 * Q + 1);
                  WX : Float := BY - AY;
                  WY : Float := -(BX - AX);
                  --  roof offsets at both ends
                  RAX : constant Float := Roof (2 * J) - AX;
                  RAY : constant Float := Roof (2 * J + 1) - AY;
                  RBX : constant Float := Roof (2 * Q) - BX;
                  RBY : constant Float := Roof (2 * Q + 1) - BY;
                  Len : constant Float := Hypot (BX - AX, BY - AY);
                  Dep : constant Float := Float'Max (Hypot (RAX, RAY), Hypot (RBX, RBY)) * Zoom;
                  Bay : constant Float := (if B.Special then 5.5 else 3.2);
                  Cols : constant Natural := Natural (Float'Floor (Len / Bay));

                  --  a quad on the wall: T along the edge, Z up (0 .. 1 of the height)
                  procedure Quad (T0, T1, Z0, Z1 : Float) is
                     function GI (Z : Float) return Float is
                        F  : constant Float := Clamp (Z, 0.0, 1.0) * 20.0;
                        I0 : constant Natural := Natural'Min (Natural (Float'Floor (F)), 19);
                     begin
                        return G (I0) + (G (I0 + 1) - G (I0)) * (F - Float (I0));
                     end GI;
                     G0 : constant Float := GI (Z0);
                     G1 : constant Float := GI (Z1);
                     procedure Pt (T, GZv : Float; First : Boolean := False) is
                        X : constant Float := AX + (BX - AX) * T + (RAX + (RBX - RAX) * T) * GZv;
                        Y : constant Float := AY + (BY - AY) * T + (RAY + (RBY - RAY) * T) * GZv;
                     begin
                        if First then
                           Move (Cr, X, Y);
                        else
                           Line (Cr, X, Y);
                        end if;
                     end Pt;
                  begin
                     Pt (T0, G0, True); Pt (T1, G0); Pt (T1, G1); Pt (T0, G1);
                     Close_Path (Cr);
                     Any := True;
                  end Quad;
               begin
                  if not B.CW then
                     WX := -WX; WY := -WY;
                  end if;
                  if WX * (Cam_X - AX) + WY * (Cam_Y - AY) > 0.0 and then Dep >= 6.0 and then Cols >= 1 then
                     declare
                        FH : constant Float := 1.0 / Float (Floors);
                     begin
                        for I in 0 .. Cols - 1 loop
                           declare
                              T0 : constant Float := Float (I) / Float (Cols);
                              TW : constant Float := 1.0 / Float (Cols);
                           begin
                              case Pass is
                                 when Windows =>
                                    for F in (if Shops then 1 else 0) .. Floors - 1 loop
                                       if B.Special then
                                          Quad (T0 + TW * 0.35, T0 + TW * 0.65,
                                                FH * (Float (F) + 0.15), FH * (Float (F) + 0.85));
                                       else
                                          Quad (T0 + TW * 0.3, T0 + TW * 0.7,
                                                FH * (Float (F) + 0.22), FH * (Float (F) + 0.78));
                                       end if;
                                    end loop;
                                 when Shopfronts =>
                                    Quad (T0 + TW * 0.1, T0 + TW * 0.9, 0.0, FH * 0.62);
                                 when Awnings_Pass =>
                                    Quad (T0 + TW * 0.06, T0 + TW * 0.94, FH * 0.62, FH * 0.9);
                              end case;
                           end;
                        end loop;
                        --  continuous Haussmann balconies on the 2nd and top floors
                        if Pass = Windows and then Floors >= 5 and then not B.Special then
                           Quad (0.02, 0.98, FH * 2.0, FH * 2.12);
                           Quad (0.02, 0.98, FH * Float (Floors - 1), FH * (Float (Floors - 1) + 0.12));
                        end if;
                     end;
                  end if;
               end;
            end loop;
            if Any then
               case Pass is
                  when Windows      => Color (Cr, C_Window, 0.72);
                  when Shopfronts   => Color (Cr, C_Shop, 0.9);
                  when Awnings_Pass => Color (Cr, Awning);
               end case;
               Fill (Cr);
            end if;
         end;
      end loop;
   end Facade;

   --  brick chimney stacks with clay pots, set in from a few roof edges
   procedure Chimneys (Cr : Cairo_Context; B : Building; Id : Natural; Roof : Float_Array;
                       Cnt : Natural; Cam_X, Cam_Y, K : Float)
   is
      type Stack is record
         X, Y, UX, UY : Float;
      end record;
      St     : array (1 .. 5) of Stack;
      N      : Natural := 0;
      CX, CY : Float := 0.0;
   begin
      if Cnt < 4 or else (B.BB.X1 - B.BB.X0) * (B.BB.Y1 - B.BB.Y0) < 60.0 then
         return;
      end if;
      for J in 0 .. Cnt - 1 loop
         CX := CX + Roof (2 * J);
         CY := CY + Roof (2 * J + 1);
      end loop;
      CX := CX / Float (Cnt); CY := CY / Float (Cnt);
      for J in 0 .. Cnt - 1 loop
         exit when N = St'Last;
         declare
            Q  : constant Natural := (J + 1) mod Cnt;
            EX : constant Float := Roof (2 * Q) - Roof (2 * J);
            EY : constant Float := Roof (2 * Q + 1) - Roof (2 * J + 1);
            L  : constant Float := Hypot (EX, EY);
         begin
            if L > 5.0 and then Hash (Float (Id) * 1.31 + Float (J) * 7.17) < 0.45 then
               declare
                  MX : constant Float := Roof (2 * J) + EX * 0.5;
                  MY : constant Float := Roof (2 * J + 1) + EY * 0.5;
                  D  : constant Float := Float'Max (Hypot (CX - MX, CY - MY), 0.01);
                  In_M : constant Float := Float'Min (2.0, D * 0.5);
                  X  : constant Float := MX + (CX - MX) / D * In_M;
                  Y  : constant Float := MY + (CY - MY) / D * In_M;
               begin
                  --  only if the matching ground point really is inside this building
                  if World.Solid (Cam_X + (X - Cam_X) / (1.0 + K), Cam_Y + (Y - Cam_Y) / (1.0 + K)) then
                     N := N + 1;
                     St (N) := (X, Y, EX / L, EY / L);
                  end if;
               end;
            end if;
         end;
      end loop;
      if N = 0 then
         return;
      end if;
      for Pass in 0 .. 2 loop
         for I in 1 .. N loop
            declare
               S  : Stack renames St (I);
               HL : constant Float := 1.0;
               HD : constant Float := 0.4;
               O  : constant Float := (if Pass = 0 then 0.45 else 0.0);
            begin
               if Pass < 2 then
                  Move (Cr, S.X + O - S.UX * HL - S.UY * HD, S.Y + O - S.UY * HL + S.UX * HD);
                  Line (Cr, S.X + O + S.UX * HL - S.UY * HD, S.Y + O + S.UY * HL + S.UX * HD);
                  Line (Cr, S.X + O + S.UX * HL + S.UY * HD, S.Y + O + S.UY * HL - S.UX * HD);
                  Line (Cr, S.X + O - S.UX * HL + S.UY * HD, S.Y + O - S.UY * HL - S.UX * HD);
                  Close_Path (Cr);
               else
                  for Pot in -1 .. 1 loop
                     Circle (Cr, S.X + S.UX * 0.6 * Float (Pot), S.Y + S.UY * 0.6 * Float (Pot), 0.2);
                  end loop;
               end if;
            end;
         end loop;
         case Pass is
            when 0 => Color (Cr, 0.0, 0.0, 0.0, 0.25);
            when 1 => Color (Cr, C_Brick);
            when others => Color (Cr, C_Pot);
         end case;
         Fill (Cr);
      end loop;
   end Chimneys;

   procedure Draw_Bridges (Cr : Cairo_Context; X0, Y0, X1, Y1 : Float) is
   begin
      Set_Line_Cap (Cr, Cairo_Line_Cap_Butt);
      Set_Line_Join (Cr, Cairo_Line_Join_Round);
      for R of Roads.all loop
         if R.Bridge and then R.BB.X1 >= X0 and then R.BB.X0 <= X1 and then R.BB.Y1 >= Y0 and then R.BB.Y0 <= Y1
         then
            case R.Kind is
               when Car_Road =>
                  Color (Cr, C_Bridge);
                  Width (Cr, R.Width + 3.0);
                  Line_Path (Cr, R.P);
                  Stroke (Cr);
                  Color (Cr, C_Asphalt);
                  Width (Cr, R.Width);
                  Line_Path (Cr, R.P);
                  Stroke (Cr);
                  if R.Width >= 10.0 then
                     Color (Cr, 0.92, 0.92, 0.88, 0.75);
                     Width (Cr, 0.25);
                     Set_Dash (Cr, (3.0, 4.0), 0.0);
                     Line_Path (Cr, R.P);
                     Stroke (Cr);
                     Set_Dash (Cr, (1 .. 0 => 0.0), 0.0);
                  end if;
               when Rail =>
                  Color (Cr, C_Ballast);
                  Width (Cr, 3.4);
                  Line_Path (Cr, R.P);
                  Stroke (Cr);
               when others =>
                  Color (Cr, C_Bridge);
                  Width (Cr, R.Width);
                  Line_Path (Cr, R.P);
                  Stroke (Cr);
            end case;
         end if;
      end loop;
      Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
   end Draw_Bridges;

   ------------------------------------------------------------------ buildings
   procedure Draw_Buildings (Cr : Cairo_Context; Cam_X, Cam_Y, Cam_H, X0, Y0, X1, Y1 : Float;
                             Zoom : Float := 10.0) is
      M     : constant Float := 40.0;
      List  : Int_Array (0 .. 8191);
      N     : Natural := 0;
      Roof  : Float_Array (0 .. 4095);
      C     : Float_Array renames Coords.all;

      procedure Sort (Lo, Hi : Integer) is   --  insertion sort is fine for nearly sorted data
         V : Integer;
         J : Integer;
      begin
         for I in Lo + 1 .. Hi loop
            V := List (I);
            J := I - 1;
            while J >= Lo and then List (J) > V loop
               List (J + 1) := List (J);
               J := J - 1;
            end loop;
            List (J + 1) := V;
         end loop;
      end Sort;
   begin
      Frame := Frame + 1;
      for BY in Clampi (Fl ((Y0 - M) / BB_Size), 0, BBH - 1) .. Clampi (Fl ((Y1 + M) / BB_Size), 0, BBH - 1) loop
         for BX in Clampi (Fl ((X0 - M) / BB_Size), 0, BBW - 1) .. Clampi (Fl ((X1 + M) / BB_Size), 0, BBW - 1) loop
            declare
               K : constant Natural := BY * BBW + BX;
            begin
               for J in B_Start (K) .. B_Start (K + 1) - 1 loop
                  declare
                     I : constant Natural := B_List (J);
                     B : Building renames Buildings (I);
                  begin
                     if B_Stamp (I) /= Frame then
                        B_Stamp (I) := Frame;
                        if B.BB.X1 >= X0 - M and then B.BB.X0 <= X1 + M
                          and then B.BB.Y1 >= Y0 - M and then B.BB.Y0 <= Y1 + M
                          and then N <= List'Last
                        then
                           List (N) := I;
                           N := N + 1;
                        end if;
                     end if;
                  end;
               end loop;
            end;
         end loop;
      end loop;
      Sort (0, N - 1);
      Set_Line_Join (Cr, Cairo_Line_Join_Miter);
      for LI in 0 .. N - 1 loop
         declare
            B   : Building renames Buildings (List (LI));
            P   : constant Natural := B.P.First;
            Cnt : constant Natural := Natural'Min (B.P.Count, Roof'Length / 2);
            K   : constant Float := B.H / Float'Max (Cam_H - B.H, 20.0);
         begin
            for J in 0 .. Cnt - 1 loop
               Roof (2 * J) := C (P + 2 * J) + (C (P + 2 * J) - Cam_X) * K;
               Roof (2 * J + 1) := C (P + 2 * J + 1) + (C (P + 2 * J + 1) - Cam_Y) * K;
            end loop;
            --  camera-facing walls, batched into 4 shade buckets
            for Shade_Bucket in 0 .. 3 loop
               declare
                  Any : Boolean := False;
               begin
                  for J in 0 .. Cnt - 1 loop
                     declare
                        Q  : constant Natural := (J + 1) mod Cnt;
                        AX : constant Float := C (P + 2 * J);
                        AY : constant Float := C (P + 2 * J + 1);
                        BX : constant Float := C (P + 2 * Q);
                        BY : constant Float := C (P + 2 * Q + 1);
                        WX : Float := BY - AY;
                        WY : Float := -(BX - AX);
                     begin
                        if not B.CW then
                           WX := -WX; WY := -WY;
                        end if;
                        if WX * (Cam_X - AX) + WY * (Cam_Y - AY) > 0.0 then
                           declare
                              NL    : constant Float := Float'Max (Hypot (WX, WY), 0.0001);
                              Light : constant Float := 0.5 + 0.5 * ((WX * (-0.5) + WY * 0.8) / NL);
                              Level : constant Natural := Natural (Clamp (Light, 0.0, 0.999) * 4.0 - 0.5);
                           begin
                              if Level = Shade_Bucket then
                                 Move (Cr, AX, AY);
                                 Line (Cr, BX, BY);
                                 Line (Cr, Roof (2 * Q), Roof (2 * Q + 1));
                                 Line (Cr, Roof (2 * J), Roof (2 * J + 1));
                                 Close_Path (Cr);
                                 Any := True;
                              end if;
                           end;
                        end if;
                     end;
                  end loop;
                  if Any then
                     Color (Cr, Wall (B.Special, Shade_Bucket * 5));
                     Fill (Cr);
                  end if;
               end;
            end loop;
            if Zoom >= 3.0 then
               Facade (Cr, B, List (LI), Roof, Cnt, Cam_X, Cam_Y, Cam_H, Zoom);
            end if;
            Move (Cr, Roof (0), Roof (1));
            for J in 1 .. Cnt - 1 loop
               Line (Cr, Roof (2 * J), Roof (2 * J + 1));
            end loop;
            Close_Path (Cr);
            Color (Cr, B.Roof);
            Fill_Preserve (Cr);
            if Zoom >= 3.0 then
               Color (Cr, Shade (B.Roof, 0.22));      --  cornice / parapet rim
               Width (Cr, 0.6);
               Stroke_Preserve (Cr);
            end if;
            Color (Cr, 0.0, 0.0, 0.0, 0.3);
            Width (Cr, 0.2);
            Stroke (Cr);
            if Zoom >= 3.0 and then not B.Special then
               Chimneys (Cr, B, List (LI), Roof, Cnt, Cam_X, Cam_Y, K);
            end if;
         end;
      end loop;
   end Draw_Buildings;

   ------------------------------------------------------------------ init
   procedure Build_Minimap is
      S  : constant Float := Minimap_Scale;
      Cr : Cairo_Context;
   begin
      Minimap := Create (Cairo_Format_ARGB32, Gint (Float'Ceiling (W * S)), Gint (Float'Ceiling (H * S)));
      Cr := Create (Minimap);
      Gfx.Scale (Cr, S);
      Color (Cr, Hex ("#3a3d40"));
      Fill_Rect (Cr, 0.0, 0.0, W, H);
      Color (Cr, Hex ("#4d7a3a"));
      for P of Parks.all loop
         Poly_Path (Cr, P.P);
      end loop;
      Fill (Cr);
      Set_Fill_Rule (Cr, Cairo_Fill_Rule_Winding);
      Color (Cr, Hex ("#3b6d92"));
      for P of World.Water.all loop
         Poly_Path (Cr, P.P);
      end loop;
      for P of World.Holes.all loop
         Poly_Path (Cr, P.P);
      end loop;
      Fill (Cr);
      Set_Fill_Rule (Cr, Cairo_Fill_Rule_Winding);
      Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
      Set_Line_Join (Cr, Cairo_Line_Join_Round);
      Color (Cr, Hex ("#8f8f8f"));
      for R of Roads.all loop
         if R.Kind = Car_Road then
            Width (Cr, Float'Max (4.0, R.Width));
            Line_Path (Cr, R.P);
            Stroke (Cr);
         end if;
      end loop;
      Color (Cr, Hex ("#5c5850"));
      for B of Buildings.all loop
         Poly_Path (Cr, B.P);
      end loop;
      Fill (Cr);
      Color (Cr, Hex ("#6a5f55"));
      Width (Cr, 3.0);
      for R of Roads.all loop
         if R.Kind = Rail then
            Line_Path (Cr, R.P);
            Stroke (Cr);
         end if;
      end loop;
      Draw_Outside (Cr, 0.0, 0.0, Float'Max (W, H));
      Destroy (Cr);
   end Build_Minimap;

   --  drops everything built for a previous map
   procedure Reset is
      procedure Free is new Ada.Unchecked_Deallocation (Bucket_Array, Bucket_Access);
      procedure Free is new Ada.Unchecked_Deallocation (Int_Array, Int_Array_Access);
   begin
      if Cache /= null then
         for T of Cache.all loop
            if T.Surf /= Null_Surface then
               Cairo.Surface.Destroy (T.Surf);
               T.Surf := Null_Surface;
            end if;
         end loop;
         Cache := null;
      end if;
      N_Cache := 0;
      if Minimap /= Null_Surface then
         Cairo.Surface.Destroy (Minimap);
         Minimap := Null_Surface;
      end if;
      Free (TB); Free (B_Start); Free (B_List); Free (B_Stamp);
   end Reset;

   procedure Init is
   begin
      Reset;
      Tiles_X := Natural (Float'Ceiling (W / TILE));
      Tiles_Y := Natural (Float'Ceiling (H / TILE));
      TB := new Bucket_Array (0 .. Tiles_X * Tiles_Y - 1);
      Cache := new Tile_Array (0 .. Tiles_X * Tiles_Y - 1);
      for I in Roads'Range loop
         B_Road (Roads (I).BB, Roads (I).Width + 4.0, I);
      end loop;
      for I in Areas'Range loop
         B_Area (Areas (I).BB, 1.0, I);
      end loop;
      for I in Parks'Range loop
         B_Park (Parks (I).BB, 1.0, I);
      end loop;
      for I in World.Water'Range loop
         B_Water (World.Water (I).BB, 2.0, I);
      end loop;
      for I in World.Holes'Range loop
         B_Hole (World.Holes (I).BB, 2.0, I);
      end loop;
      for I in Buildings'Range loop
         B_Bld (Buildings (I).BB, 3.0, I);
      end loop;
      --  building buckets
      BBW := Natural (Float'Ceiling (W / BB_Size));
      BBH := Natural (Float'Ceiling (H / BB_Size));
      declare
         Cnt   : Int_Array (0 .. BBW * BBH) := (others => 0);
         Total : Natural := 0;
         procedure Each (I : Natural; Act : access procedure (K : Natural)) is
            B : BBox renames Buildings (I).BB;
         begin
            for BY in Clampi (Fl (B.Y0 / BB_Size), 0, BBH - 1) .. Clampi (Fl (B.Y1 / BB_Size), 0, BBH - 1) loop
               for BX in Clampi (Fl (B.X0 / BB_Size), 0, BBW - 1) .. Clampi (Fl (B.X1 / BB_Size), 0, BBW - 1) loop
                  Act (BY * BBW + BX);
               end loop;
            end loop;
         end Each;
         procedure Count (K : Natural) is
         begin
            Cnt (K + 1) := Cnt (K + 1) + 1;
            Total := Total + 1;
         end Count;
      begin
         for I in Buildings'Range loop
            Each (I, Count'Access);
         end loop;
         for I in 1 .. Cnt'Last loop
            Cnt (I) := Cnt (I) + Cnt (I - 1);
         end loop;
         B_Start := new Int_Array'(Cnt);
         B_List := new Int_Array (0 .. Total - 1);
         declare
            Fill_Pos : Int_Array := Cnt;
            Cur      : Natural := 0;
            procedure Put (K : Natural) is
            begin
               B_List (Fill_Pos (K)) := Cur;
               Fill_Pos (K) := Fill_Pos (K) + 1;
            end Put;
         begin
            for I in Buildings'Range loop
               Cur := I;
               Each (I, Put'Access);
            end loop;
         end;
      end;
      B_Stamp := new Int_Array'(Buildings'Range => 0);
      for S in Boolean loop
         for I in 0 .. 15 loop
            declare
               L : constant Float := Float (I) / 15.0;
            begin
               Wall (S, I) := HSL (40.0, (if S then 14.0 else 22.0),
                                   (if S then 52.0 + L * 26.0 else 46.0 + L * 30.0));
            end;
         end loop;
      end loop;
      Build_Minimap;
   end Init;

end World_Render;
