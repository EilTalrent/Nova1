with Nova.Hardware; use Nova.Hardware;
with Nova.Console;  use Nova.Console;
with Nova.Math;     use Nova.Math;
with Nova.Video;    use Nova.Video;
with Palette_Plan;  use Palette_Plan;
with Scenery;

package body Night_Sky is

   --  Tiles
   Star_Big    : constant Tile_Index := 128;
   Star_Small  : constant Tile_Index := 129;
   Star_Faint  : constant Tile_Index := 130;
   Meteor_Head : constant Tile_Index := 131;
   Trail_Tile  : constant Tile_Index := 137;

   --  Sprites
   subtype Star_Id  is Sprite_Id range 16 .. 55;
   subtype Trail_Id is Sprite_Id range 10 .. 14;
   Meteor_Id : constant Sprite_Id := 9;

   type Star is record
      X     : Fixed;
      Y     : Integer;
      Kind  : Tile_Index;
      Speed : Fixed;
   end record;

   Stars : array (Star_Id) of Star;

   type Point is record
      X, Y : Fixed;
   end record;

   Meteor_Active : Boolean := False;
   Meteor_Pos    : Point;
   Meteor_Vel    : Point;
   Trail         : array (Trail_Id) of Point;
   Next_Meteor   : Natural := 40;

   procedure Draw_Dot (T : Tile_Index; Pattern : String) is
      --  Pattern is 64 characters, row by row; digits are colours.
   begin
      for I in 0 .. 63 loop
         Tiles (T) (I / 8, I mod 8) :=
           Color_Index (Character'Pos (Pattern (Pattern'First + I)) - Character'Pos ('0'));
      end loop;
   end Draw_Dot;

   procedure Build is
   begin
      Draw_Dot (Star_Big,
        "00000000" & "00020000" & "00020000" & "02212200" &
        "00020000" & "00020000" & "00000000" & "00000000");
      Draw_Dot (Star_Small,
        "00000000" & "00000000" & "00030000" & "00313000" &
        "00030000" & "00000000" & "00000000" & "00000000");
      Draw_Dot (Star_Faint,
        "00000000" & "00000000" & "00000000" & "00030000" &
        "00000000" & "00000000" & "00000000" & "00000000");
      Draw_Dot (Meteor_Head,
        "00000000" & "00002200" & "00021120" & "00211112" &
        "00021120" & "00002200" & "00000000" & "00000000");
      Draw_Dot (Trail_Tile,
        "00000000" & "00000000" & "00033000" & "00322300" &
        "00322300" & "00033000" & "00000000" & "00000000");

      Palette (Bank_Color (Meteor_Bank, 1)) := Make_RGB (255, 255, 240);
      Palette (Bank_Color (Meteor_Bank, 2)) := Make_RGB (150, 220, 255);
      Palette (Bank_Color (Meteor_Bank, 3)) := Make_RGB (70, 110, 200);

      for S in Star_Id loop
         Stars (S) :=
           (X     => Fixed (Random (0, 255)),
            Y     => 10 + Random (0, 100) * Random (0, 100) / 100,  --  denser up high
            Kind  => Star_Big + Tile_Index (Random (0, 5) / 2),
            Speed => Fixed (Random (1, 3)) / 16);
      end loop;
   end Build;

   procedure Launch_Meteor is
   begin
      Meteor_Active := True;
      Meteors_Seen  := Meteors_Seen + 1;
      Meteor_Pos    := (X => Fixed (Random (120, 300)), Y => Fixed (Random (-20, 10)));
      Meteor_Vel    := (X => -Fixed (Random (20, 32)) / 8, Y => Fixed (Random (8, 14)) / 8);
      Trail         := [others => Meteor_Pos];
   end Launch_Meteor;

   procedure Update (Frame : Natural) is
      Night : constant Natural := Scenery.Darkness;
   begin
      --  Stars fade in as the sky darkens and twinkle on three phases.
      for C in Color_Index range 1 .. 3 loop
         declare
            Twinkle : constant Fixed :=
              Sin (Angle ((Frame * (3 + Natural (C) * 2) + Natural (C) * 80) mod 256));
            Level   : constant Integer := 120 + Night / 2 + Floor (Twinkle * 40);
         begin
            Palette (Bank_Color (Star_Bank, C)) :=
              Mix (Make_RGB (150, 70, 120), Make_RGB (240, 240, 255),
                   Natural'Max (0, Natural'Min (256, Level)));
         end;
      end loop;

      for S in Star_Id loop
         declare
            St : Star renames Stars (S);
         begin
            St.X := St.X - St.Speed;
            if St.X < -8.0 then
               St.X := St.X + 264.0;
            end if;
            Place_Sprite (S, Floor (St.X), St.Y, St.Kind,
                          Bank => Star_Bank, Behind_BG0 => True, Windowed => True);
         end;
      end loop;

      --  Falling stars
      if not Meteor_Active and then Frame >= Next_Meteor then
         Launch_Meteor;
      end if;

      if Meteor_Active then
         --  Shift the trail: each segment takes the place of the one ahead.
         for T in reverse Trail_Id range Trail_Id'First + 1 .. Trail_Id'Last loop
            Trail (T) := Trail (T - 1);
         end loop;
         Trail (Trail_Id'First) := Meteor_Pos;

         Meteor_Pos := (X => Meteor_Pos.X + Meteor_Vel.X,
                        Y => Meteor_Pos.Y + Meteor_Vel.Y);

         Place_Sprite (Meteor_Id, Floor (Meteor_Pos.X), Floor (Meteor_Pos.Y),
                       Meteor_Head, Bank => Meteor_Bank, Behind_BG0 => True,
                       Windowed => True);
         for T in Trail_Id loop
            Place_Sprite (T, Floor (Trail (T).X), Floor (Trail (T).Y), Trail_Tile,
                          Bank => Meteor_Bank, Behind_BG0 => True, Windowed => True);
         end loop;

         --  Gone once the whole trail has dropped behind the horizon or off
         --  the left edge.
         if Trail (Trail_Id'Last).Y > Fixed (Scenery.Horizon)
           or else Trail (Trail_Id'Last).X < -16.0
         then
            Meteor_Active := False;
            OAM (Meteor_Id).Attr.Visible := False;
            for T in Trail_Id loop
               OAM (T).Attr.Visible := False;
            end loop;
            Next_Meteor := Frame + Random (30, 150);
         end if;
      end if;
   end Update;

end Night_Sky;
