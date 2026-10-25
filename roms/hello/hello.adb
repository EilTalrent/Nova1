with Nova.Hardware; use Nova.Hardware;
with Nova.Console;  use Nova.Console;
with Nova.Video;    use Nova.Video;

procedure Hello is
begin
   Debug_Line ("Hello from Ada on NOVA-1!");
   Palette (0) := Make_RGB (16, 24, 64);
   Palette (Bank_Color (15, 1)) := Make_RGB (255, 220, 120);
   Clear (BG1);
   Put_Text (BG1, 10, 6, "HELLO FROM ADA!");
   Control := (BG1 => True, others => False);
   for F in 1 .. 30 loop
      Put_Number (BG1, 12, 12, Natural (Frame_Count), 5);
      Wait_VSync;
   end loop;
   Debug ("done after frames: "); Debug (Integer (Frame_Count)); Debug_Line ("");
end Hello;
