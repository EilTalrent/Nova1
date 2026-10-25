package body Nova.Math is

   function Floor (F : Fixed) return Integer is
      I : constant Integer := Integer (F);  --  rounds to nearest
   begin
      return (if Fixed (I) > F then I - 1 else I);
   end Floor;

end Nova.Math;
