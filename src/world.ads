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

--  Map data (from data/paris.bin), collision grid, road graphs and street names.
--  World coordinates are metres: x east, y south, origin at the NW corner.
with Util; use Util;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package World is

   W, H   : Float := 0.0;
   GW, GH : Natural := 0;          --  collision grid size (1 cell = 1 m)

   --  A polygon / polyline: Count points starting at float index First in Coords
   type Poly is record
      First : Natural := 0;
      Count : Natural := 0;
   end record;
   Coords : Float_Array_Access;

   type BBox is record
      X0, Y0, X1, Y1 : Float;
   end record;

   type Road_Kind is (Car_Road, Ped_Area, Footway, Rail);
   type Road is record
      Kind   : Road_Kind;
      Width  : Float;
      Bridge : Boolean;
      P      : Poly;
      BB     : BBox;
   end record;
   type Road_Array is array (Natural range <>) of Road;
   type Road_Access is access Road_Array;

   type Shape is record
      P  : Poly;
      BB : BBox;
   end record;
   type Shape_Array is array (Natural range <>) of Shape;
   type Shape_Access is access Shape_Array;

   type Building is record
      H       : Float;
      Special : Boolean;
      P       : Poly;
      BB      : BBox;
      CW      : Boolean;    --  screen-clockwise winding
      Roof    : RGB;
   end record;
   type Building_Array is array (Natural range <>) of Building;
   type Building_Access is access Building_Array;

   Roads     : Road_Access;
   Areas, Parks, Water, Holes : Shape_Access;
   Buildings : Building_Access;    --  sorted by height (low first)

   type Landmark is record
      Name : Unbounded_String;
      X, Y : Float;
   end record;
   type Landmark_Array is array (Natural range <>) of Landmark;
   type Landmark_Access is access Landmark_Array;
   Landmarks : Landmark_Access;

   --  playable area (the Peripherique); outside it is solid. Count = 0: whole box
   Boundary : Poly;
   function In_Bounds (X, Y : Float) return Boolean;

   --  city settings stored in the map file (version 3): names, texts, currency, cheat words.
   --  Meta returns Default when the map does not set Key (older maps: Paris defaults).
   function Meta (Key, Default : String) return String;
   --  the I-th item (1-based) of a ';'-separated Meta list, "" past the end
   function Meta_Item (Key, Default : String; I : Positive) return String;

   procedure Load (Path : String);   --  load map + build grid and indices

   --  collision grid: 0 free, 1 building, 2 water, 3 bridge over water (land on top, water below)
   function Cell (X, Y : Float) return Natural;
   pragma Inline (Cell);
   function Solid (X, Y : Float) return Boolean is (Cell (X, Y) = 1);
   function Blocked (X, Y : Float) return Boolean is (Cell (X, Y) in 1 | 2);
   function Land (X, Y : Float) return Boolean is (Cell (X, Y) in 0 | 3);        --  cars and people
   function Navigable (X, Y : Float) return Boolean is (Cell (X, Y) in 2 | 3);   --  boats
   --  Boat: free means navigable water; otherwise free land (and water unless Water_Solid)
   procedure Normal_At (X, Y : Float; Water_Solid : Boolean; NX, NY : out Float; Boat : Boolean := False);
   function LOS (AX, AY, BX, BY : Float) return Boolean;

   --  road graphs
   type Graph_Kind is (Car_Graph, Ped_Graph);
   function Node_Count (K : Graph_Kind) return Natural;
   function NX (K : Graph_Kind; I : Natural) return Float;
   function NY (K : Graph_Kind; I : Natural) return Float;
   function Degree (K : Graph_Kind; I : Natural) return Natural;
   function Neighbor (K : Graph_Kind; I : Natural; J : Positive) return Natural;
   function Nearest (K : Graph_Kind; X, Y, Max_R : Float) return Integer;  --  -1 if none
   function Two_Way (A, B : Natural) return Boolean;                       --  car graph
   function Undirected_Degree (K : Graph_Kind; I : Natural) return Natural;  --  in + out neighbours
   function Undirected_Neighbor (K : Graph_Kind; I : Natural; J : Positive) return Natural;
   --  A* on the car graph ignoring one-way rules (used by police)
   procedure Find_Path (A, B : Integer; Path : out Int_Array; Len : out Natural);

   function Street_At (X, Y : Float) return String;
   function District_At (X, Y : Float) return String;

end World;
