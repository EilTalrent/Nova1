package body System.Assertions is

   procedure Last_Chance_Handler (Message : System.Address; Line : Integer)
     with Import, Convention => C,
          External_Name => "__gnat_last_chance_handler", No_Return;

   --  Msg is e.g. "failed precondition from nova-video.ads:22". Pass it on as
   --  a C string with line 0, meaning "the message says it all".
   procedure Raise_Assert_Failure (Msg : String) is
      Buf : String (1 .. 80) := [others => ASCII.NUL];
      Len : constant Natural := Natural'Min (Msg'Length, Buf'Length - 1);
   begin
      Buf (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      Last_Chance_Handler (Buf'Address, 0);
   end Raise_Assert_Failure;

end System.Assertions;
