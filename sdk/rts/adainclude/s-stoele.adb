package body System.Storage_Elements is

   --  Address is a modular type in System's private part, which this child
   --  package's body can see, so these are plain type conversions.

   function "+" (Left : Address; Right : Storage_Offset) return Address is
     (Left + Address'Mod (Right));

   function "+" (Left : Storage_Offset; Right : Address) return Address is
     (Address'Mod (Left) + Right);

   function "-" (Left : Address; Right : Storage_Offset) return Address is
     (Left - Address'Mod (Right));

   function "-" (Left, Right : Address) return Storage_Offset is
     (Storage_Offset'Base (Integer_Address (Left) - Integer_Address (Right)));

   function To_Address (Value : Integer_Address) return Address is
     (Address (Value));

   function To_Integer (Value : Address) return Integer_Address is
     (Integer_Address (Value));

end System.Storage_Elements;
