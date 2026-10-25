with Nova.Hardware; use Nova.Hardware;
with Nova.Console;  use Nova.Console;
with Nova.Math;     use Nova.Math;
with Nova.Video;    use Nova.Video;
with Palette_Plan;  use Palette_Plan;

package body Ship is

   Ship_Tile  : constant Tile_Index := 132;   --  132 .. 135, a 16x16 sprite
   Spark_Tile : constant Tile_Index := 136;
   Ship_Id    : constant Sprite_Id  := 0;
   subtype Spark_Id is Sprite_Id range 1 .. 8;

   --  Pixel art straight in the source. a/b hull, c cockpit, d engine glow.
   type Art_16 is array (0 .. 15) of String (1 .. 16);
   Ship_Art : constant Art_16 :=
     ["................",
      "................",
      "...bb...........",
      "...bab..........",
      "...baab.........",
      "..dbbaaab.......",
      ".ddbaaaaabbb....",
      "ddbbaaaacccaab..",
      "ddbbaaaacccaaab.",
      ".ddbaaaaabbbbb..",
      "..dbbaaab.......",
      "...baab.........",
      "...bab..........",
      "...bb...........",
      "................",
      "................"];

   function Art_Color (C : Character) return Color_Index is
     (case C is
         when 'a' => 1,
         when 'b' => 2,
         when 'c' => 3,
         when 'd' => 4,
         when others => 0);

   type Spark is record
      X, Y : Fixed;
      Life : Natural;
   end record;

   Sparks     : array (Spark_Id) of Spark := [others => (0.0, 0.0, 0)];
   Next_Spark : Spark_Id := Spark_Id'First;

   X : Fixed := 40.0;
   Y : Fixed := 60.0;
   Idle_Frames : Natural := 1_000;

   function Autopilot return Boolean is (Idle_Frames > 120);

   procedure Build is
   begin
      for PY in 0 .. 15 loop
         for PX in 0 .. 15 loop
            Tiles (Ship_Tile + Tile_Index ((PY / 8) * 2 + PX / 8)) (PY mod 8, PX mod 8) :=
              Art_Color (Ship_Art (PY) (PX + 1));
         end loop;
      end loop;

      for PY in 0 .. 7 loop
         for PX in 0 .. 7 loop
            declare
               D2 : constant Integer := (PX * 2 - 7) ** 2 + (PY * 2 - 7) ** 2;
            begin
               Tiles (Spark_Tile) (PY, PX) :=
                 (if D2 <= 10 then 1 elsif D2 <= 26 then 2 else 0);
            end;
         end loop;
      end loop;

      Palette (Bank_Color (Ship_Bank, 1)) := Make_RGB (200, 210, 240);
      Palette (Bank_Color (Ship_Bank, 2)) := Make_RGB (70, 80, 140);
      Palette (Bank_Color (Ship_Bank, 3)) := Make_RGB (90, 250, 255);
      Palette (Bank_Color (Spark_Bank, 1)) := Make_RGB (255, 240, 160);
      Palette (Bank_Color (Spark_Bank, 2)) := Make_RGB (255, 120, 40);
   end Build;

   procedure Update (Frame : Natural) is
      Speed : constant Fixed := (if Is_Pressed (A) then 2.5 else 1.5);
      Boost : constant Boolean := Is_Pressed (A);
   begin
      if Any_Pressed then
         Idle_Frames := 0;
      elsif Idle_Frames < Natural'Last then
         Idle_Frames := Idle_Frames + 1;
      end if;

      if Autopilot then
         --  A figure eight: x follows sin(t), y follows sin(2t).
         declare
            T  : constant Angle := Angle ((Frame / 2) mod 256);
            TX : constant Fixed := 104.0 + Sin (T) * 80;
            TY : constant Fixed := 70.0 + Sin (T * 2) * 34;
         begin
            X := X + (TX - X) / 8;
            Y := Y + (TY - Y) / 8;
         end;
      else
         if Is_Pressed (Left)  then X := X - Speed; end if;
         if Is_Pressed (Right) then X := X + Speed; end if;
         if Is_Pressed (Up)    then Y := Y - Speed; end if;
         if Is_Pressed (Down)  then Y := Y + Speed; end if;
         X := Fixed'Max (0.0, Fixed'Min (240.0, X));
         Y := Fixed'Max (8.0, Fixed'Min (168.0, Y));
      end if;

      --  Engine flicker
      Palette (Bank_Color (Ship_Bank, 4)) :=
        (if Frame mod 4 < 2 then Make_RGB (255, 200, 80) else Make_RGB (255, 90, 40));

      Place_Sprite (Ship_Id, Floor (X), Floor (Y), Ship_Tile,
                    Size => Size_16, Bank => Ship_Bank);

      --  Exhaust: a ring buffer of sparks that drift back and burn out.
      if Frame mod (if Boost then 1 else 3) = 0 then
         Sparks (Next_Spark) := (X => X - 2.0, Y => Y + 4.0 + Fixed (Random (-1, 1)), Life => 16);
         Next_Spark := (if Next_Spark = Spark_Id'Last then Spark_Id'First else Next_Spark + 1);
      end if;

      for S in Spark_Id loop
         declare
            Sp : Spark renames Sparks (S);
         begin
            if Sp.Life > 0 then
               Sp.Life := Sp.Life - 1;
               Sp.X := Sp.X - 1.75;
               Place_Sprite (S, Floor (Sp.X), Floor (Sp.Y), Spark_Tile, Bank => Spark_Bank);
            else
               OAM (S).Attr.Visible := False;
            end if;
         end;
      end loop;
   end Update;

end Ship;
