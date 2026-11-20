/*
 * Fake battery for the Windows VM with the GTX 1650 Mobile.
 * The NVIDIA driver for mobile GPUs stops with Code 43 when the machine has no battery.
 * Build: iasl ssdt-battery.asl  (gives ssdt-battery.aml; host/01-host-setup.sh does this)
 */
DefinitionBlock ("", "SSDT", 1, "BOCHS", "BATTERY", 0x00000001)
{
    Scope (\_SB)
    {
        Device (BAT0)
        {
            Name (_HID, EisaId ("PNP0C0A"))
            Name (_UID, Zero)
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }
            Method (_BIF, 0, NotSerialized)
            {
                Return (Package (0x0D)
                {
                    One, 0x1770, 0x1770, One, 0x39D0, 0x0258, 0x012C,
                    0x3C, 0x3C, "", "", "LION", ""
                })
            }
            Method (_BST, 0, NotSerialized)
            {
                Return (Package (0x04) { Zero, Zero, 0x1770, 0x39D0 })
            }
        }
    }
}
