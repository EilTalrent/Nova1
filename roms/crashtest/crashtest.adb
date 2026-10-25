--  Deliberately breaks an Ada range check to show the crash screen.
with Nova.Hardware; use Nova.Hardware;
with Nova.Console;  use Nova.Console;

procedure Crashtest is
   Bank : Palette_Bank := 12;
begin
   for F in 1 .. 10 loop
      Wait_VSync;
      Bank := Bank + 1;   --  13, 14, 15, then 16: out of range!
   end loop;
end Crashtest;
