/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20251212 (64-bit version)
 * Copyright (c) 2000 - 2025 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of /Users/miqbalf/Documents/HACKINTOSH_EFI/EFI_20260121/OC/ACPI/SSDT-HDEF.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x0000016D (365)
 *     Revision         0x02
 *     Checksum         0xB6
 *     OEM ID           "HACK"
 *     OEM Table ID     "HDEF"
 *     OEM Revision     0x00000000 (0)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20200925 (538970405)
 */
DefinitionBlock ("", "SSDT", 2, "HACK", "HDEF", 0x00000000)
{
    External (_SB_.PCI0, DeviceObj)
    External (_SB_.PCI0.HDAS, DeviceObj)

    Scope (\_SB.PCI0)
    {
        If (_OSI ("Darwin"))
        {
            Name (HDAS._STA, Zero)  // _STA: Status
            Device (HDEF)
            {
                Name (_ADR, 0x001F0003)  // _ADR: Address
                Method (_DSM, 4, NotSerialized)  // _DSM: Device-Specific Method
                {
                    If ((Arg2 == Zero))
                    {
                        Return (Buffer (One)
                        {
                             0x03                                             // .
                        })
                    }

                    Return (Package (0x10)
                    {
                        "name", 
                        "Audio Controller", 
                        "AAPL,slot-name", 
                        "Built-In", 
                        "model", 
                        "Apple Device Pci. Realtek ALC 295 Audio Controller", 
                        "device_type", 
                        "Audio Controller", 
                        "layout-id", 
                        Unicode ("!"), 
                        "alctsel", 
                        Buffer (0x04)
                        {
                             0x01, 0x00, 0x00, 0x00                           // ....
                        }, 

                        "alc-verbs", 
                        Buffer (0x04)
                        {
                             0x01, 0x00, 0x00, 0x00                           // ....
                        }, 

                        "hda-gfx", 
                        "onboard-1"
                    })
                }
            }
        }
    }
}

