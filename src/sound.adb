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

with Interfaces;    use Interfaces;
with Interfaces.C;  use Interfaces.C;
with Interfaces.C.Strings;
with System;
use type System.Address;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

package body Sound is

   Rate  : constant := 44_100;
   Block : constant := 512;                 --  frames per write (~11.6 ms)
   TwoPi : constant Float := 2.0 * Ada.Numerics.Pi;

   ------------------------------------------------------------------ libpulse-simple
   type PA_Sample_Spec is record
      Format   : int;
      Rate     : unsigned;
      Channels : unsigned_char;
   end record;
   pragma Convention (C, PA_Sample_Spec);

   type PA_Buffer_Attr is record
      Max_Length, T_Length, Pre_Buf, Min_Req, Frag_Size : Unsigned_32;
   end record;
   pragma Convention (C, PA_Buffer_Attr);

   PA_STREAM_PLAYBACK : constant int := 1;
   PA_SAMPLE_S16LE    : constant int := 3;

   function PA_Simple_New (Server : System.Address; Name : Interfaces.C.Strings.chars_ptr;
                           Dir : int; Dev : System.Address;
                           Stream_Name : Interfaces.C.Strings.chars_ptr;
                           Spec : access PA_Sample_Spec; Map : System.Address;
                           Attr : access PA_Buffer_Attr; Error : access int) return System.Address;
   pragma Import (C, PA_Simple_New, "pa_simple_new");
   function PA_Simple_Write (S : System.Address; Data : System.Address; Bytes : size_t;
                             Error : access int) return int;
   pragma Import (C, PA_Simple_Write, "pa_simple_write");
   procedure PA_Simple_Free (S : System.Address);
   pragma Import (C, PA_Simple_Free, "pa_simple_free");

   ------------------------------------------------------------------ shared control
   type Request is record
      E : Effect;
      V : Float;
   end record;
   type Request_Array is array (1 .. 64) of Request;

   protected Control is
      procedure Push (E : Effect; V : Float);
      procedure Take (Q : out Request_Array; N : out Natural);
      procedure Set_Engine (On : Boolean; Speed : Float);
      procedure Set_Siren (V : Float);
      procedure Set_Amb (On : Boolean);
      function Amb return Boolean;
      procedure Set_Music (V : Float);
      function Music return Float;
      procedure Flip_Mute (Now_Muted : out Boolean);
      procedure Request_Stop;
      procedure Params (On : out Boolean; Speed, Siren : out Float; Muted, Stop : out Boolean);
   private
      Queue  : Request_Array;
      Count  : Natural := 0;
      Eng_On : Boolean := False;
      Eng_Sp : Float := 0.0;
      Sir_V  : Float := 0.0;
      Amb_On : Boolean := False;
      Mus_V  : Float := 0.0;
      Mute   : Boolean := False;
      Halt   : Boolean := False;
   end Control;

   protected body Control is
      procedure Push (E : Effect; V : Float) is
      begin
         if Count < Queue'Last then
            Count := Count + 1;
            Queue (Count) := (E, V);
         end if;
      end Push;
      procedure Take (Q : out Request_Array; N : out Natural) is
      begin
         Q := Queue;
         N := Count;
         Count := 0;
      end Take;
      procedure Set_Engine (On : Boolean; Speed : Float) is
      begin
         Eng_On := On;
         Eng_Sp := Speed;
      end Set_Engine;
      procedure Set_Siren (V : Float) is
      begin
         Sir_V := V;
      end Set_Siren;
      procedure Set_Amb (On : Boolean) is
      begin
         Amb_On := On;
      end Set_Amb;
      procedure Set_Music (V : Float) is
      begin
         Mus_V := V;
      end Set_Music;
      function Music return Float is (Mus_V);
      function Amb return Boolean is (Amb_On);
      procedure Flip_Mute (Now_Muted : out Boolean) is
      begin
         Mute := not Mute;
         Now_Muted := Mute;
      end Flip_Mute;
      procedure Request_Stop is
      begin
         Halt := True;
      end Request_Stop;
      procedure Params (On : out Boolean; Speed, Siren : out Float; Muted, Stop : out Boolean) is
      begin
         On := Eng_On; Speed := Eng_Sp; Siren := Sir_V; Muted := Mute; Stop := Halt;
      end Params;
   end Control;

   ------------------------------------------------------------------ voices
   type Wave is (Noise, Square, Sine, Triangle);
   type Filter is (None, Low_Pass, Band_Pass);

   type Voice is record
      Active   : Boolean := False;
      W        : Wave := Noise;
      Wait     : Natural := 0;          --  samples before it starts
      Len, Pos : Natural := 0;
      Gain     : Float := 0.0;
      F0, F1   : Float := 440.0;        --  frequency slide (exponential)
      Phase    : Float := 0.0;
      Flt      : Filter := None;
      LP_A, LP : Float := 0.0;          --  one-pole low pass
      HP_A, HP : Float := 0.0;          --  second pole for band pass
      Sustain  : Boolean := False;      --  flat envelope with short release (horn)
   end record;

   Voices : array (1 .. 64) of Voice;

   function Coef (Cutoff : Float) return Float is (1.0 - Exp (-TwoPi * Cutoff / Float (Rate)));

   procedure Add (W : Wave; Dur, Gain : Float; F0 : Float := 0.0; F1 : Float := 0.0;
                  Delay_S : Float := 0.0; Flt : Filter := None; Cutoff : Float := 1000.0;
                  Sustain : Boolean := False) is
   begin
      for V of Voices loop
         if not V.Active then
            V := (Active => True, W => W, Wait => Natural (Delay_S * Float (Rate)),
                  Len => Natural'Max (1, Natural (Dur * Float (Rate))), Pos => 0, Gain => Gain,
                  F0 => F0, F1 => (if F1 = 0.0 then F0 else F1), Phase => 0.0,
                  Flt => Flt, LP_A => Coef (Cutoff), LP => 0.0,
                  HP_A => Coef (Cutoff * 0.5), HP => 0.0, Sustain => Sustain);
            return;
         end if;
      end loop;
   end Add;

   type Notes is array (1 .. 4) of Float;
   type Natural_Triple is array (1 .. 3) of Natural;
   Up_Jingle   : constant Notes := (523.0, 659.0, 784.0, 1046.0);
   Down_Jingle : constant Notes := (392.0, 330.0, 262.0, 196.0);

   procedure Trigger (E : Effect; Vol : Float) is
      V : constant Float := Float'Max (0.0, Float'Min (1.5, Vol));
   begin
      if V < 0.01 then
         return;
      end if;
      case E is
         when Shot_Pistol =>
            Add (Noise, 0.22, 0.55 * V, Flt => Low_Pass, Cutoff => 1700.0);
            Add (Square, 0.08, 0.12 * V, 120.0, 40.0);
         when Shot_SMG =>
            Add (Noise, 0.10, 0.55 * V, Flt => Low_Pass, Cutoff => 2600.0);
            Add (Square, 0.08, 0.12 * V, 180.0, 40.0);
         when Punch =>
            Add (Noise, 0.07, 0.5 * V, Flt => Low_Pass, Cutoff => 500.0);
         when Explosion =>
            Add (Noise, 1.6, 1.0 * V, Flt => Low_Pass, Cutoff => 300.0);
            Add (Noise, 0.4, 0.5 * V, Flt => Low_Pass, Cutoff => 1400.0);
            Add (Sine, 0.8, 0.4 * V, 70.0, 25.0);
         when Crash =>
            Add (Noise, 0.25, 0.7 * V, Flt => Low_Pass, Cutoff => 700.0 + V * 900.0);
         when Splat =>
            Add (Noise, 0.18, 0.6 * V, Flt => Low_Pass, Cutoff => 260.0);
         when Splash =>
            Add (Noise, 1.0, 0.9 * V, Flt => Band_Pass, Cutoff => 1500.0);
         when Pickup =>
            Add (Square, 0.08, 0.08 * V, 880.0);
            Add (Square, 0.12, 0.08 * V, 1320.0, Delay_S => 0.07);
         when Horn =>
            Add (Square, 0.35, 0.06 * V, 392.0, Sustain => True);
            Add (Square, 0.35, 0.05 * V, 494.0, Sustain => True);
         when Job_Passed =>
            for I in 0 .. 3 loop
               Add (Square, 0.25, 0.07 * V, Up_Jingle (I + 1), Delay_S => Float (I) * 0.12);
            end loop;
         when Job_Failed =>
            for I in 0 .. 3 loop
               Add (Triangle, 0.3, 0.12 * V, Down_Jingle (I + 1), Delay_S => Float (I) * 0.15);
            end loop;
         when Phone_Ring =>
            Add (Square, 0.06, 0.05 * V, 1200.0);
            Add (Square, 0.06, 0.05 * V, 1500.0, Delay_S => 0.08);
         when Chime =>              --  a golden pave: bell arpeggio
            for I in 0 .. 3 loop
               Add (Sine, 0.9, 0.16 * V, Up_Jingle (I + 1) * 2.0, Delay_S => Float (I) * 0.06);
               Add (Sine, 0.5, 0.05 * V, Up_Jingle (I + 1) * 5.04, Delay_S => Float (I) * 0.06);
            end loop;
         when Flutter =>            --  pigeons taking off: a burst of wing beats
            for I in 0 .. 7 loop
               Add (Noise, 0.07, 0.22 * V, Delay_S => Float (I) * 0.045 + Float (I mod 3) * 0.01,
                    Flt => Band_Pass, Cutoff => 1800.0 + Float (I mod 4) * 300.0);
            end loop;
         when Clang =>              --  heavy manhole cover
            Add (Sine, 1.2, 0.30 * V, 220.0, 214.0);
            Add (Sine, 0.9, 0.18 * V, 587.0, 580.0);
            Add (Sine, 0.6, 0.10 * V, 1113.0);
            Add (Noise, 0.12, 0.5 * V, Flt => Low_Pass, Cutoff => 900.0);
         when Shot_Shotgun =>
            Add (Noise, 0.35, 0.8 * V, Flt => Low_Pass, Cutoff => 1100.0);
            Add (Square, 0.12, 0.15 * V, 90.0, 35.0);
         when Launch =>             --  rocket / grenade throw: a rising whoosh
            Add (Noise, 0.45, 0.45 * V, Flt => Band_Pass, Cutoff => 700.0);
            Add (Sine, 0.4, 0.12 * V, 180.0, 520.0);
         when Cannon =>             --  tank gun
            Add (Noise, 0.9, 1.0 * V, Flt => Low_Pass, Cutoff => 420.0);
            Add (Sine, 0.6, 0.5 * V, 55.0, 30.0);
            Add (Noise, 0.15, 0.6 * V, Flt => Low_Pass, Cutoff => 2500.0);
         when Cheat =>
            for I in 0 .. 5 loop
               Add (Triangle, 0.18, 0.12 * V, 440.0 * 2.0 ** (Float (I) / 4.0), Delay_S => Float (I) * 0.05);
            end loop;
      end case;
   end Trigger;

   ------------------------------------------------------------------ street accordion
   --  An original little waltz in A minor (3/4): melody as MIDI notes, 0 = hold.
   Beat_S : constant Float := 0.36;
   type Beat_Array is array (0 .. 47) of Natural;
   Melody : constant Beat_Array :=
     (69, 72, 76,  81, 79, 76,  77, 76, 74,  76, 0, 0,
      74, 77, 81,  79, 77, 74,  76, 74, 72,  71, 0, 0,
      72, 76, 81,  83, 81, 79,  77, 81, 77,  76, 0, 72,
      74, 71, 68,  69, 71, 72,  71, 68, 64,  69, 0, 0);
   type Bar_Array is array (0 .. 15) of Natural;
   Roots : constant Bar_Array := (45, 45, 50, 45, 50, 43, 48, 40, 45, 40, 50, 45, 40, 45, 40, 45);
   Minor : constant array (0 .. 15) of Boolean :=
     (True, True, True, True, True, False, False, False, True, False, True, True, False, True, False, True);

   function Hz (M : Natural) return Float is (440.0 * 2.0 ** (Float (M - 69) / 12.0));

   procedure Play_Beat (B : Natural; V : Float; Delay_S : Float) is
      Bar : constant Natural := B / 3;
      M   : constant Natural := Melody (B);
   begin
      if M > 0 then
         declare
            Len : Natural := 1;
         begin
            while B + Len <= Melody'Last and then Melody (B + Len) = 0 loop
               Len := Len + 1;
            end loop;
            --  musette: two slightly detuned reeds
            Add (Square, Float (Len) * Beat_S * 0.95, 0.030 * V, Hz (M) * 0.997, Delay_S => Delay_S,
                 Flt => Low_Pass, Cutoff => 2400.0, Sustain => True);
            Add (Square, Float (Len) * Beat_S * 0.95, 0.030 * V, Hz (M) * 1.004, Delay_S => Delay_S,
                 Flt => Low_Pass, Cutoff => 2400.0, Sustain => True);
         end;
      end if;
      if B mod 3 = 0 then                                           --  oom
         Add (Triangle, Beat_S * 0.9, 0.22 * V, Hz (Roots (Bar)), Delay_S => Delay_S, Sustain => True);
      else                                                          --  pah, pah
         declare
            R : constant Natural := 57 + (Roots (Bar) - 57) mod 12;
         begin
            for N of Natural_Triple'(R, R + (if Minor (Bar) then 3 else 4), R + 7) loop
               Add (Square, Beat_S * 0.45, 0.010 * V, Hz (N), Delay_S => Delay_S, Flt => Low_Pass,
                    Cutoff => 1500.0, Sustain => True);
            end loop;
         end;
      end if;
   end Play_Beat;

   Seed : Unsigned_32 := 22_222;
   function White return Float is
   begin
      Seed := Seed * 1_664_525 + 1_013_904_223;
      return Float (Shift_Right (Seed, 8)) / 8_388_608.0 - 1.0;
   end White;

   function Sample (V : in out Voice) return Float is
      T   : constant Float := Float (V.Pos) / Float (V.Len);
      Env : Float;
      S   : Float;
      F   : Float;
   begin
      if V.Sustain then
         Env := (if T < 0.8 then 1.0 else (1.0 - T) / 0.2);
      else
         Env := Exp (-6.9 * T);              --  ~ -60 dB at the end
      end if;
      if V.W = Noise then
         S := White;
      else
         F := V.F0 * (V.F1 / V.F0) ** T;
         V.Phase := V.Phase + F / Float (Rate);
         V.Phase := V.Phase - Float'Floor (V.Phase);
         case V.W is
            when Square   => S := (if V.Phase < 0.5 then 1.0 else -1.0);
            when Sine     => S := Sin (TwoPi * V.Phase);
            when Triangle => S := 4.0 * abs (V.Phase - 0.5) - 1.0;
            when Noise    => null;
         end case;
      end if;
      case V.Flt is
         when None => null;
         when Low_Pass =>
            V.LP := V.LP + V.LP_A * (S - V.LP);
            S := V.LP;
         when Band_Pass =>
            V.LP := V.LP + V.LP_A * (S - V.LP);
            V.HP := V.HP + V.HP_A * (V.LP - V.HP);
            S := (V.LP - V.HP) * 2.0;
      end case;
      V.Pos := V.Pos + 1;
      if V.Pos >= V.Len then
         V.Active := False;
      end if;
      return S * Env * V.Gain;
   end Sample;

   ------------------------------------------------------------------ mixer task
   Started : Boolean := False;
   pragma Atomic (Started);

   task type Mixer is
      entry Go;
   end Mixer;
   type Mixer_Access is access Mixer;
   The_Mixer : Mixer_Access;

   task body Mixer is
      Spec : aliased PA_Sample_Spec := (PA_SAMPLE_S16LE, Rate, 1);
      Attr : aliased PA_Buffer_Attr :=
        (Max_Length => 16#FFFF_FFFF#, T_Length => 4096, Pre_Buf => 16#FFFF_FFFF#,
         Min_Req => 16#FFFF_FFFF#, Frag_Size => 16#FFFF_FFFF#);
      Err  : aliased int := 0;
      Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String ("PAVE");
      Strm : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String ("game");
      Dev  : System.Address;
      Buf  : array (1 .. Block) of Integer_16;
      Q    : Request_Array;
      N    : Natural;
      On, Muted, Halt : Boolean;
      Speed, Siren_V  : Float;
      --  engine / siren state
      Eng_Phase, Eng_Phase2, Eng_LP, Eng_Gain, Eng_Freq, Eng_Speed : Float := 0.0;
      Rumble_LP, Amb_LP, Amb_LP2, Amb_Gain : Float := 0.0;
      Amb_Phase : Float := 0.0;
      Sir_Phase, Sir_Gain : Float := 0.0;
      Clock : Natural := 0;
      Mus_Beat : Natural := 0;
      Mus_Next : Natural := 0;     --  sample clock of the next accordion beat
   begin
      accept Go;
      Dev := PA_Simple_New (System.Null_Address, Name, PA_STREAM_PLAYBACK, System.Null_Address,
                            Strm, Spec'Access, System.Null_Address, Attr'Access, Err'Access);
      Interfaces.C.Strings.Free (Name);
      Interfaces.C.Strings.Free (Strm);
      if Dev = System.Null_Address then
         Started := False;          --  no audio server: play silently
      else
      loop
         Control.Params (On, Speed, Siren_V, Muted, Halt);
         exit when Halt;
         Control.Take (Q, N);
         for I in 1 .. N loop
            Trigger (Q (I).E, Q (I).V);
         end loop;
         declare
            MV : constant Float := Control.Music;
         begin
            if MV > 0.01 and then not Muted then
               if Mus_Next < Clock then
                  Mus_Next := Clock;
               end if;
               while Mus_Next < Clock + Block loop        --  schedule beats falling in this block
                  Play_Beat (Mus_Beat, Float'Min (1.0, MV), Float (Mus_Next - Clock) / Float (Rate));
                  Mus_Beat := (Mus_Beat + 1) mod 48;
                  Mus_Next := Mus_Next + Natural (Beat_S * Float (Rate));
               end loop;
            else
               Mus_Beat := 0;
            end if;
         end;
         declare
            --  ambient engine: quiet, low, no gear steps; speed mostly adds road rumble
            Sp          : constant Float := Float'Min (Speed, 40.0);
            Eng_Target  : constant Float := (if On and then not Muted then 0.020 + Sp / 2600.0 else 0.0);
            Freq_Target : constant Float := 32.0 + Sp * 1.1;
            Eng_A       : constant Float := Coef (110.0 + Sp * 4.0);
            Rumble_A    : constant Float := Coef (70.0 + Sp * 3.0);
            Amb_Target  : constant Float := (if Control.Amb and then not Muted then 1.0 else 0.0);
            Amb_A       : constant Float := Coef (160.0);
            Amb_A2      : constant Float := Coef (60.0);
            Sir_Target  : constant Float := (if Muted then 0.0 else Siren_V * 0.07);
         begin
            for I in Buf'Range loop
               declare
                  Mix : Float := 0.0;
               begin
                  --  engine: two detuned soft oscillators + tyre/road rumble, slow fades
                  Eng_Gain := Eng_Gain + (Eng_Target - Eng_Gain) * 0.00008;      --  ~0.3 s
                  Eng_Freq := Eng_Freq + (Freq_Target - Eng_Freq) * 0.00012;
                  Eng_Speed := Eng_Speed + (Sp - Eng_Speed) * 0.0001;
                  if Eng_Gain > 0.0002 then
                     Eng_Phase := Eng_Phase + Eng_Freq / Float (Rate);
                     Eng_Phase := Eng_Phase - Float'Floor (Eng_Phase);
                     Eng_Phase2 := Eng_Phase2 + Eng_Freq * 1.007 / Float (Rate);
                     Eng_Phase2 := Eng_Phase2 - Float'Floor (Eng_Phase2);
                     Eng_LP := Eng_LP + Eng_A
                       * ((Sin (TwoPi * Eng_Phase) + 0.5 * (4.0 * abs (Eng_Phase2 - 0.5) - 1.0)) - Eng_LP);
                     Rumble_LP := Rumble_LP + Rumble_A * (White - Rumble_LP);
                     Mix := Mix + Eng_Gain
                       * (Eng_LP * 0.8 + Rumble_LP * (1.0 + Eng_Speed * 0.12));
                  end if;
                  --  city ambience: slowly breathing low noise bed
                  Amb_Gain := Amb_Gain + (Amb_Target - Amb_Gain) * 0.00003;
                  if Amb_Gain > 0.0005 then
                     Amb_Phase := Amb_Phase + 0.06 / Float (Rate);
                     Amb_Phase := Amb_Phase - Float'Floor (Amb_Phase);
                     Amb_LP := Amb_LP + Amb_A * (White - Amb_LP);
                     Amb_LP2 := Amb_LP2 + Amb_A2 * (Amb_LP - Amb_LP2);
                     Mix := Mix + (Amb_LP - Amb_LP2 * 0.6) * Amb_Gain
                       * 0.11 * (0.8 + 0.2 * Sin (TwoPi * Amb_Phase));
                  end if;
                  --  siren: French two-tone "pin-pon"
                  Sir_Gain := Sir_Gain + (Sir_Target - Sir_Gain) * 0.0005;
                  if Sir_Gain > 0.0005 then
                     Sir_Phase := Sir_Phase
                       + (if (Clock / (Rate * 55 / 100)) mod 2 = 0 then 435.0 else 580.0) / Float (Rate);
                     Sir_Phase := Sir_Phase - Float'Floor (Sir_Phase);
                     Mix := Mix + (4.0 * abs (Sir_Phase - 0.5) - 1.0) * Sir_Gain;
                  end if;
                  if not Muted then
                     for V of Voices loop
                        if V.Active then
                           if V.Wait > 0 then
                              V.Wait := V.Wait - 1;
                           else
                              Mix := Mix + Sample (V);
                           end if;
                        end if;
                     end loop;
                  else
                     for V of Voices loop
                        V.Active := False;
                     end loop;
                  end if;
                  Mix := Mix * 0.45;
                  Mix := Mix / (1.0 + abs Mix * 0.3);          --  gentle limiter
                  Mix := Float'Max (-1.0, Float'Min (1.0, Mix));
                  Buf (I) := Integer_16 (Mix * 32_000.0);
                  Clock := Clock + 1;
               end;
            end loop;
         end;
         exit when PA_Simple_Write (Dev, Buf'Address, size_t (Block * 2), Err'Access) < 0;
      end loop;
      PA_Simple_Free (Dev);
      Started := False;
      end if;
   end Mixer;

   ------------------------------------------------------------------ API
   procedure Start is
   begin
      if Started then
         return;
      end if;
      Started := True;
      The_Mixer := new Mixer;
      The_Mixer.Go;
   end Start;

   procedure Stop is
   begin
      Control.Request_Stop;
   end Stop;

   function Running return Boolean is (Started);

   procedure Play (E : Effect; Volume : Float := 1.0) is
   begin
      if Started then
         Control.Push (E, Volume);
      end if;
   end Play;

   procedure Set_Engine (On : Boolean; Speed : Float) is
   begin
      Control.Set_Engine (On, Speed);
   end Set_Engine;

   procedure Set_Siren (Volume : Float) is
   begin
      Control.Set_Siren (Volume);
   end Set_Siren;

   procedure Set_Ambience (On : Boolean) is
   begin
      Control.Set_Amb (On);
   end Set_Ambience;

   procedure Set_Music (Volume : Float) is
   begin
      Control.Set_Music (Volume);
   end Set_Music;

   function Toggle_Mute return Boolean is
      M : Boolean;
   begin
      Control.Flip_Mute (M);
      return M;
   end Toggle_Mute;

end Sound;
