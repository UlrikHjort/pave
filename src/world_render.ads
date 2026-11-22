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

--  Map rendering: cached ground tiles, 2.5D extruded buildings and the minimap.
with Cairo; use Cairo;

package World_Render is

   procedure Init;   --  after World.Load

   --  Cr must already be in world space (metres). Budget = max tiles rendered this call.
   procedure Draw_Ground (Cr : Cairo_Context; X0, Y0, X1, Y1 : Float; Budget : Natural := 4);
   --  bridge decks in a rectangle, drawn again on top of boats passing underneath
   procedure Draw_Bridges (Cr : Cairo_Context; X0, Y0, X1, Y1 : Float);

   --  Buildings with roofs projected away from the camera (CamH = virtual camera height)
   --  Zoom = screen pixels per metre (controls level of detail)
   procedure Draw_Buildings (Cr : Cairo_Context; Cam_X, Cam_Y, Cam_H, X0, Y0, X1, Y1 : Float;
                             Zoom : Float := 10.0);

   Minimap       : Cairo_Surface := Cairo.Null_Surface;
   Minimap_Scale : constant Float := 0.25;   --  pixels per metre

end World_Render;
