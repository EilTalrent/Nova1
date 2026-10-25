------------------------------------------------------------------------------
--  STARFALL : a NOVA-1 cartridge, written in Ada.
--
--  The main loop is the classic console shape: update everything, then sleep
--  until vsync. PRISM draws whatever video memory holds at that moment.
------------------------------------------------------------------------------

with Nova.Hardware; use Nova.Hardware;
with Nova.Console;  use Nova.Console;
with Nova.Math;     use Nova.Math;
with Nova.Video;    use Nova.Video;
with Palette_Plan;  use Palette_Plan;
with Scenery;
with Night_Sky;
with Ship;

procedure Starfall is

   Frame : Natural := 0;
   Title_Frames : constant := 330;

   procedure Show_Title (Visible : Boolean) is
      procedure Line (Row : Map_Row; Col : Map_Column; Text : String; Bank : Palette_Bank) is
      begin
         if Visible then
            Put_Text (BG1, Row, Col, Text, Bank);
         else
            Put_Text (BG1, Row, Col, [Text'Range => ' '], Bank);
         end if;
      end Line;
   begin
      Line (2, 8, "S T A R F A L L", Title_Bank);
      Line (4, 7, "A NOVA-1 CARTRIDGE", Hud_Bank);
      Line (5, 9, "WRITTEN IN ADA", Accent_Bank);
   end Show_Title;

   procedure Update_HUD is
      Pulse : constant Fixed := Sin (Angle ((Frame * 3) mod 256));
   begin
      Palette (Bank_Color (Title_Bank, 1)) :=
        Mix (Make_RGB (255, 220, 110), Make_RGB (255, 90, 170), 128 + Floor (Pulse * 127));

      Put_Number (BG1, 0, 26, Natural'Min (999, CPU_Load_Percent), 3, Hud_Bank);
      Put_Number (BG1, 23, 7, Frame mod 1_000_000, 6, Hud_Bank);
      Put_Number (BG1, 23, 28, Night_Sky.Meteors_Seen mod 1000, 3, Hud_Bank);

      if Ship.Autopilot and then Frame > Title_Frames and then Frame mod 64 < 44 then
         Put_Text (BG1, 21, 6, "DEMO - PRESS ANY BUTTON", Accent_Bank);
      else
         Put_Text (BG1, 21, 6, "                       ", Accent_Bank);
      end if;

      if Frame = Title_Frames then
         Show_Title (False);
      end if;
   end Update_HUD;

begin
   Debug_Line ("STARFALL: hello from Ada! building the scene...");

   --  Black out and build everything with the screen off.
   Brightness := 0;
   Control := (others => False);
   Hide_All_Sprites;
   Clear (BG1);

   Scenery.Build;
   Night_Sky.Build;
   Ship.Build;

   Palette (Bank_Color (Hud_Bank, 1))    := Make_RGB (236, 226, 255);
   Palette (Bank_Color (Accent_Bank, 1)) := Make_RGB (110, 240, 255);

   Put_Text (BG1, 0, 1, "NOVA-1", Accent_Bank);
   Put_Text (BG1, 0, 22, "CPU    %", Hud_Bank);
   Put_Text (BG1, 23, 1, "FRAME", Hud_Bank);
   Put_Text (BG1, 23, 20, "METEORS", Hud_Bank);
   Show_Title (True);

   Control := (BG0 | BG1 | Sprites | Line_Scroll | Line_Backdrop => True);
   Debug_Line ("STARFALL: scene built, entering main loop");

   loop
      Scenery.Update (Frame);
      Night_Sky.Update (Frame);
      Ship.Update (Frame);
      Update_HUD;

      --  Fade in over the first second.
      Brightness := Brightness_Level (Natural'Min (256, Frame * 4));

      if Frame mod 300 = 299 then
         Debug ("STARFALL: frame ");
         Debug (Frame + 1);
         Debug (", cpu load ");
         Debug (CPU_Load_Percent);
         Debug ("%, meteors ");
         Debug (Night_Sky.Meteors_Seen);
         Debug_Line ("");
      end if;

      Frame := Frame + 1;
      Wait_VSync;
   end loop;
end Starfall;
