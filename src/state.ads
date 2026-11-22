-- ***************************************************************************
--                      PAVÉ - State
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

--  All mutable game state. Entities live in fixed pools and are referred to
--  by slot index (0 = none), which keeps the simulation allocation-free.
with Util; use Util;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package State is

   Max_Cars  : constant := 130;
   Max_Peds  : constant := 260;
   Max_Path  : constant := 400;

   subtype Car_Ref is Natural range 0 .. Max_Cars;
   subtype Ped_Ref is Natural range 0 .. Max_Peds;

   ---------------------------------------------------------------- cars
   type Car_Type is (Compact, Sedan, Sport, Taxi, Van, Bus, Police, Scooter,
                     Speedboat, Tourboat, Police_Boat,          --  boats: water is their road
                     Escargot, Fournil, Fusee, Tank, Helicopter, Plane);   --  secret vehicles
   subtype Boat_Type is Car_Type range Speedboat .. Police_Boat;
   subtype Air_Type is Car_Type range Helicopter .. Plane;
   function Is_Boat (K : Car_Type) return Boolean is (K in Boat_Type);
   function Is_Air (K : Car_Type) return Boolean is (K in Air_Type);

   type Car_Params is record
      Len, Wid, Max, Acc, Brake, Grip, Steer, HP, Mass : Float;
   end record;

   Params : constant array (Car_Type) of Car_Params :=
     (Compact => (3.8, 1.70, 36.0,  9.0, 22.0,  9.0, 2.7, 100.0, 1.0),
      Sedan   => (4.6, 1.85, 42.0, 10.0, 22.0,  8.5, 2.4, 120.0, 1.3),
      Sport   => (4.4, 1.90, 62.0, 17.0, 26.0, 10.0, 2.6,  90.0, 1.1),
      Taxi    => (4.7, 1.85, 42.0, 10.0, 22.0,  8.5, 2.4, 120.0, 1.3),
      Van     => (5.3, 2.05, 31.0,  7.0, 18.0,  8.0, 2.1, 170.0, 2.0),
      Bus     => (11.5, 2.55, 23.0, 4.0, 14.0,  9.0, 1.4, 320.0, 6.0),
      Police  => (4.7, 1.90, 54.0, 14.0, 26.0, 10.0, 2.6, 160.0, 1.4),
      Scooter => (1.9, 0.75, 30.0, 12.0, 20.0, 11.0, 3.2, 60.0, 0.35),
      Escargot => (3.9, 1.60, 19.0, 5.0, 16.0, 7.5, 2.7, 900.0, 3.0),    --  slow, nearly indestructible
      Fournil  => (5.0, 2.00, 30.0, 7.0, 18.0, 8.0, 2.1, 170.0, 2.0),    --  bakery van
      Fusee    => (4.6, 1.90, 72.0, 30.0, 32.0, 13.0, 2.4, 120.0, 1.1),   --  absurdly fast
      Tank     => (7.0, 3.40, 14.0, 4.5, 14.0, 12.0, 1.6, 3000.0, 20.0),   --  crushes everything
      Speedboat   => (5.6, 2.10, 30.0, 9.0, 6.0, 2.6, 2.3, 150.0, 1.2),   --  low grip: boats slide
      Tourboat    => (24.0, 4.6, 8.0, 1.6, 3.0, 3.0, 0.7, 2000.0, 15.0),
      Police_Boat => (6.6, 2.40, 29.0, 9.0, 6.0, 3.0, 2.2, 300.0, 1.6),
      Helicopter  => (11.0, 2.6, 38.0, 10.0, 10.0, 9.0, 1.8, 400.0, 2.0),
      Plane       => (9.0, 3.0, 70.0, 9.0, 12.0, 9.0, 1.1, 300.0, 2.5));

   Car_Names : constant array (Car_Type) of Unbounded_String :=
     (To_Unbounded_String ("Citadine"), To_Unbounded_String ("Berline"),
      To_Unbounded_String ("Bolide"), To_Unbounded_String ("Taxi"),
      To_Unbounded_String ("Fourgon"), To_Unbounded_String ("Autobus"),
      To_Unbounded_String ("Police"), To_Unbounded_String ("Scooter"),
      To_Unbounded_String ("Vedette"), To_Unbounded_String ("Bateau-mouche"),
      To_Unbounded_String ("Police fluviale"),
      To_Unbounded_String ("Escargot"), To_Unbounded_String ("Fournil"), To_Unbounded_String ("Fusee"),
      To_Unbounded_String ("Char d'assaut"), To_Unbounded_String ("Helico"), To_Unbounded_String ("Avion"));

   type Traffic_Mix is array (1 .. 14) of Car_Type;
   Mix : constant Traffic_Mix :=
     (Compact, Compact, Compact, Sedan, Sedan, Sedan, Taxi, Taxi, Van, Van, Sport, Bus, Scooter, Scooter);

   type Driver_Kind is (No_Driver, Player_Driver, AI_Driver);
   type AI_Mode is (Traffic, Pursuit);
   type Culprit is (Nobody, By_Player, By_Cop, By_NPC);

   type Path_Array is array (1 .. Max_Path) of Integer;

   type AI_State is record
      Mode       : AI_Mode := Traffic;
      Path       : Path_Array := (others => 0);
      Len        : Natural := 0;
      Idx        : Positive := 1;
      Lane       : Float := 2.1;
      Cruise     : Float := 10.0;
      Stuck_T    : Float := 0.0;
      Rev_T      : Float := 0.0;
      Panic      : Float := 0.0;
      Repath     : Float := 0.0;
      Wait_T     : Float := 0.0;
      Blocked_By : Car_Ref := 0;
   end record;

   type Car is record
      Active     : Boolean := False;
      Serial     : Natural := 0;
      Kind       : Car_Type := Compact;
      X, Y, A    : Float := 0.0;
      VX, VY, AV : Float := 0.0;
      Color      : RGB := (0.5, 0.5, 0.5);
      HP         : Float := 100.0;
      Fire_T     : Float := 0.0;
      Sink_T     : Float := 0.0;
      Dead, Sunk, Explode, Keep, Siren, Deployed, Skidding : Boolean := False;
      Driver     : Driver_Kind := No_Driver;
      AI         : AI_State;
      Throttle   : Float := 0.0;
      Steer      : Float := 0.0;
      Handbrake  : Boolean := False;
      Has_Skid   : Boolean := False;
      Skid       : Float_Array (0 .. 3) := (others => 0.0);
      Last_Hit   : Culprit := Nobody;
      Turret     : Float := 0.0;      --  tank: absolute turret angle
      Z          : Float := 0.0;      --  aircraft: height above the ground (m)
      Gun_T      : Float := 0.0;      --  tank: time until the next shell
   end record;

   Cars : array (1 .. Max_Cars) of Car;

   ---------------------------------------------------------------- peds
   type Ped_Mode is (Walk, Flee, Idle);
   type Ped_Role is (Citizen, Mime, Musician, Marcher);   --  street-life characters (Secrets)

   type Ped is record
      Active      : Boolean := False;
      Serial      : Natural := 0;
      X, Y, A     : Float := 0.0;
      HP          : Float := 100.0;
      Dead        : Boolean := False;
      Cop, Is_Player, Target, Keep, Armed : Boolean := False;
      Shirt, Hair, Skin : RGB := (0.5, 0.5, 0.5);
      Walk_Speed  : Float := 1.4;
      Phase       : Float := 0.0;
      Moving      : Boolean := False;
      Mode        : Ped_Mode := Walk;
      Flee_T, Flee_X, Flee_Y : Float := 0.0;
      Node, Prev  : Integer := -1;
      Lat         : Float := 0.0;
      Shoot_T     : Float := 0.0;
      Dead_T      : Float := 0.0;
      Stuck       : Float := 0.0;
      Home_Car    : Car_Ref := 0;
      Role        : Ped_Role := Citizen;
   end record;

   Peds : array (1 .. Max_Peds) of Ped;

   Serial_Counter : Natural := 0;

   ---------------------------------------------------------------- player
   Player     : Ped_Ref := 0;
   Player_Car : Car_Ref := 0;
   Max_Weapon : constant := 5;
   Weapon     : Natural := 1;   --  0 fists, 1 pistol, 2 SMG, 3 shotgun, 4 grenades, 5 rockets
   Ammo       : array (0 .. Max_Weapon) of Integer := (1_000_000, 45, 0, 0, 0, 0);
   Armor      : Float := 0.0;
   Bail_Warn  : Boolean := False;

   type Weapon_Info is record
      Rate, Dmg, Rng, Spread : Float;
      Melee : Boolean;
   end record;
   Weapons : constant array (0 .. Max_Weapon) of Weapon_Info :=
     ((0.38, 34.0, 1.5, 0.0, True),
      (0.30, 60.0, 60.0, 0.025, False),
      (0.085, 30.0, 55.0, 0.07, False),
      (0.85, 22.0, 24.0, 0.16, False),      --  shotgun: six pellets
      (0.90, 170.0, 6.0, 0.0, False),       --  grenade: blast power / radius
      (1.30, 220.0, 5.5, 0.0, False));      --  rocket: blast power / radius
   Weapon_Names : constant array (0 .. Max_Weapon) of Unbounded_String :=
     (To_Unbounded_String ("Fists"), To_Unbounded_String ("Pistol"),
      To_Unbounded_String ("SMG"), To_Unbounded_String ("Shotgun"),
      To_Unbounded_String ("Grenades"), To_Unbounded_String ("Rockets"));

   ---------------------------------------------------------------- projectiles
   type Proj_Kind is (Grenade, Rocket, Shell);
   type Projectile is record
      Active     : Boolean := False;
      Kind       : Proj_Kind := Grenade;
      X, Y, Z, VX, VY, VZ, T, Dist : Float := 0.0;
      By         : Culprit := Nobody;
      Owner_Ped  : Ped_Ref := 0;
      Owner_Car  : Car_Ref := 0;
   end record;
   Projs : array (1 .. 48) of Projectile;

   ---------------------------------------------------------------- effects
   type Part_Kind is (Smoke, Fire, Boom, Spark, Blood_Drop, Debris, Flash, Splash);
   type Particle is record
      Active : Boolean := False;
      Kind   : Part_Kind := Smoke;
      X, Y, VX, VY, Life, Max, S, Drag : Float := 0.0;
      Top    : Boolean := False;
   end record;
   Max_Parts : constant := 800;
   Parts : array (1 .. Max_Parts) of Particle;

   type Seg is record
      X0, Y0, X1, Y1 : Float;
   end record;
   Max_Skids : constant := 1600;
   Skids     : array (0 .. Max_Skids - 1) of Seg;
   Skid_Head, Skid_Count : Natural := 0;

   type Splat is record
      X, Y, R, A : Float;
   end record;
   Max_Blood : constant := 250;
   Blood     : array (0 .. Max_Blood - 1) of Splat;
   Blood_Head, Blood_Count : Natural := 0;
   Max_Scorch : constant := 60;
   Scorch     : array (0 .. Max_Scorch - 1) of Splat;
   Scorch_Head, Scorch_Count : Natural := 0;

   type Tracer is record
      X0, Y0, X1, Y1, Life : Float := 0.0;
   end record;
   Tracers : array (1 .. 40) of Tracer;

   type Pickup_Kind is (Cash, Pistol_Ammo, SMG_Ammo, Health, Body_Armor,
                        Shotgun_Ammo, Grenade_Box, Rocket_Ammo);
   type Pickup is record
      Active : Boolean := False;
      Kind   : Pickup_Kind := Cash;
      X, Y   : Float := 0.0;
      N      : Integer := 0;
      Fixed  : Boolean := False;
   end record;
   Pickups : array (1 .. 120) of Pickup;
   Pickup_Respawn : Float := 0.0;

   ---------------------------------------------------------------- game flow
   type Game_Mode is (Title, Play, Paused, Dead);
   Mode       : Game_Mode := Title;
   Dead_T     : Float := 0.0;
   Busted     : Boolean := False;
   Time       : Float := 0.0;
   Heat       : Float := 0.0;
   Seen_T     : Float := 99.0;
   Bust_T     : Float := 0.0;
   Star_Flash : Float := 0.0;
   Hurt_Flash : Float := 0.0;
   Shake      : Float := 0.0;
   Money      : Integer := 0;
   Won        : Boolean := False;
   Win_Delay  : Float := 0.0;
   Police_T   : Float := 0.0;
   Populated  : Boolean := False;

   ---------------------------------------------------------------- camera / view
   Cam_X, Cam_Y : Float := 0.0;
   Cam_Z        : Float := 10.0;    --  pixels per metre
   Cam_ZS       : Float := 0.0;
   Cam_Scale    : Float := 1.0;     --  extra zoom (used by --capture)
   Screen_W     : Float := 1280.0;
   Screen_H     : Float := 800.0;
   View_X0, View_Y0, View_X1, View_Y1, View_HD, View_W : Float := 0.0;

   ---------------------------------------------------------------- messages
   Message      : Unbounded_String;
   Msg_T        : Float := 0.0;
   Big_Text     : Unbounded_String;
   Big_Sub      : Unbounded_String;
   Big_Color    : RGB := (1.0, 0.82, 0.29);
   Big_T        : Float := 0.0;
   Big_Max      : Float := 1.0;
   Street_Shown : Unbounded_String;
   District     : Unbounded_String;
   Street_T     : Float := 0.0;
   Street_Check : Float := 0.0;

   ---------------------------------------------------------------- missions
   type Spot is record
      Name           : Unbounded_String;
      PX, PY, CX, CY : Float := 0.0;
   end record;
   Spots   : array (1 .. 80) of Spot;
   N_Spots : Natural := 0;

   type Phone is record
      S    : Positive := 1;
      Cool : Float := 0.0;
      On   : Boolean := True;    --  False if its place is not on this map
   end record;
   N_Phones : constant := 16;
   Phones   : array (1 .. N_Phones) of Phone;

   type Mission_Kind is (Delivery, Steal, Hit_Job, Escape);
   type Mission_State is record
      Kind        : Mission_Kind := Delivery;
      Phone_Idx   : Positive := 1;
      Dest        : Positive := 1;
      TX, TY      : Float := 0.0;
      Has_Target_Pos : Boolean := True;
      Timer       : Float := 0.0;
      Has_Timer   : Boolean := False;
      Reward      : Integer := 0;
      M_Car       : Car_Ref := 0;
      M_Target    : Ped_Ref := 0;
      Stage       : Natural := 0;
      Time2       : Float := 0.0;
      Target_Dead : Boolean := False;
      Car_Lost    : Boolean := False;
   end record;
   Has_Mission   : Boolean := False;
   Mis           : Mission_State;
   Mission_Count : Natural := 0;
   Hospital, Station : Positive := 1;

end State;
