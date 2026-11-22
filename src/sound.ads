-- ***************************************************************************
--                      PAVÉ - Sound
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

--  Synthesized sound: a mixer task streams to PulseAudio (libpulse-simple).
--  All calls are cheap and non-blocking; before Start they do nothing.
package Sound is

   type Effect is (Shot_Pistol, Shot_SMG, Punch, Explosion, Crash, Splat, Splash,
                   Pickup, Horn, Job_Passed, Job_Failed, Phone_Ring,
                   Chime, Flutter, Clang, Cheat, Shot_Shotgun, Launch, Cannon);

   procedure Start;                  --  open the audio device and start mixing
   procedure Stop;                   --  stop the mixer task (call before exit)
   function Running return Boolean;

   procedure Play (E : Effect; Volume : Float := 1.0);
   procedure Set_Engine (On : Boolean; Speed : Float);   --  player's engine, speed in m/s
   procedure Set_Siren (Volume : Float);                  --  0 .. 1
   procedure Set_Ambience (On : Boolean);                 --  soft city background hum
   procedure Set_Music (Volume : Float);                  --  street accordion, 0 .. 1
   function Toggle_Mute return Boolean;                   --  returns True when now muted

end Sound;
