-- ***************************************************************************
--                      PAVÉ - Game
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

--  Game logic: player, combat, police, missions, spawning, camera.
with Util;
with State;

package Game is

   procedure Init;                 --  after World.Load and World_Render.Init
   procedure Frame (DT : Float);   --  input + simulation for one rendered frame
   procedure Start_Game;           --  leave the title screen
   function Started_Once return Boolean;   --  a game is in progress (title reached from pause)

   function Stars return Natural;

   --  helpers shared with Secrets
   procedure Say (S : String; Dur : Float := 4.0);
   procedure Show_Big (S : String; C : Util.RGB; Dur : Float := 2.5; Sub : String := "");
   procedure Particle (X, Y : Float; K : State.Part_Kind);
   procedure Clear_Wanted;          --  no stars, pursuing police go back to normal traffic
   function On_Screen (X, Y : Float; M : Float := 8.0) return Boolean;
   procedure Screen_To_World (SX, SY : Float; WX, WY : out Float);

   --  current navigation target for the HUD arrow / minimap
   procedure Nav_Target (Has : out Boolean; X, Y : out Float; Is_Phone : out Boolean);

   --  exercises every mission type programmatically; prints results
   procedure Self_Test;

   --  prints why stopped AI cars are stopped (for the bench)
   procedure Traffic_Report;

end Game;
