-- ***************************************************************************
--                      PAVÉ - Secrets
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

--  Secrets and street life: golden paves, secret cars, catacomb manholes, pigeons,
--  street characters (mime, accordionist, protest march), cheat words, and the
--  Discoveries journal, saved per world in data/progress-<world>.txt.
with Cairo; use Cairo;

package Secrets is

   Persist : Boolean := True;          --  False in headless tests: never touch the save file

   procedure Init;                     --  after Game.Init: place everything, load progress
   procedure Update (DT : Float);      --  every simulation step
   procedure Paused;                   --  every frame while paused: cheat words

   --  hooks used by Game
   function Try_Manhole return Boolean;          --  player pressed "enter": climbed down?
   function Busy return Boolean;                 --  in the catacombs (player can't act)
   function Strike return Boolean;               --  general strike: traffic stands still
   function Hidden_In_Crowd return Boolean;      --  player blends into the protest march
   function Respawn_Armor return Boolean;        --  pave rewards
   function Respawn_SMG return Boolean;
   procedure Noise (X, Y, R : Float);            --  gunshot / horn / explosion: pigeons flee

   --  drawing (world coordinates unless noted)
   procedure Draw_Ground (Cr : Cairo_Context);   --  paves, manholes, pigeons on the ground
   procedure Draw_Air (Cr : Cairo_Context; Cam_X, Cam_Y, Cam_H : Float);   --  flying pigeons
   procedure Draw_Overlay (Cr : Cairo_Context);  --  screen space: catacomb fade
   procedure Draw_Journal (Cr : Cairo_Context; X, Y, S : Float);   --  screen space

   procedure Self_Test;                --  headless check of every secret
   type Shot_Proc is access procedure (Name : String);
   Shot : Shot_Proc := null;           --  set by the app to save screenshots during Self_Test

end Secrets;
