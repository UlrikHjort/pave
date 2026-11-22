-- ***************************************************************************
--                      PAVÉ - Maps
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

--  The installable worlds, the remembered choice, and the background installer
--  (tools/get_map.py) that downloads and builds a world from OpenStreetMap.
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Maps is

   type World_Id is (Small, Large, Copenhagen);   --  Small / Large: Central Paris / All of Paris

   function Title (W : World_Id) return String;
   function About (W : World_Id) return String;
   function Download_Info (W : World_Id) return String;
   function Path (W : World_Id) return String;           --  data/paris-<w>.bin
   function Installed (W : World_Id) return Boolean;
   function Any_Installed return Boolean;

   Selected : World_Id := Small;    --  highlighted in the menus
   Current  : World_Id := Small;    --  the world that is loaded
   Loaded   : Boolean := False;
   Loading  : Boolean := False;    --  a world is about to be loaded (show a loading screen)

   --  picks the world to start with: the last one played, else any installed one
   procedure Choose_Startup;
   procedure Remember (W : World_Id);
   function Progress_Path return String;    --  discoveries saved for the current world

   --  background installation
   function Can_Install return Boolean;                   --  python3 and the tools are there
   procedure Start_Install (W : World_Id);
   procedure Cancel_Install;
   function Installing return Boolean;
   Install_World : World_Id := Small;
   procedure Poll (DT : Float);      --  call every frame; reads the installer's progress

   Stage         : Unbounded_String;    --  download / build / done / error
   Done, Total   : Natural := 0;
   Message       : Unbounded_String;
   Unit          : Unbounded_String;    --  what Done / Total count: "parts" or "MB" 
   Just_Finished : Boolean := False;    --  an install completed (cleared by the caller)
   Failed        : Boolean := False;

   procedure Stop;                      --  at exit: stop a running installer

end Maps;
