/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20251212 (64-bit version)
 * Copyright (c) 2000 - 2025 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of /Users/miqbalf/Documents/HACKINTOSH_EFI/EFI_20260121/OC/ACPI/SSDT-ETH.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x000001F1 (497)
 *     Revision         0x02
 *     Checksum         0x18
 *     OEM ID           "HACK"
 *     OEM Table ID     "ETH"
 *     OEM Revision     0x00000000 (0)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20200925 (538970405)
 */
DefinitionBlock ("", "SSDT", 2, "HACK", "ETH", 0x00000000)
{
    External (_SB_.PCI0.RP14, DeviceObj)
    External (_SB_.PCI0.RP14.PXSX, DeviceObj)

    Scope (\_SB.PCI0.RP14)
    {
        If (_OSI ("Darwin"))
        {
            Name (PXSX._STA, Zero)  // _STA: Status
            Device (ETH0)
            {
                Name (_ADR, Zero)  // _ADR: Address
                Method (_DSM, 4, NotSerialized)  // _DSM: Device-Specific Method
                {
                    If ((Arg2 == Zero))
                    {
                        Return (Buffer (One)
                        {
                             0x03                                             // .
                        })
                    }

                    Return (Package (0x0A)
                    {
                        "name", 
                        "ETH0", 
                        "AAPL,slot-name", 
                        "Built-In", 
                        "built-in", 
                        Buffer (One)
                        {
                             0x00                                             // .
                        }, 

                        "model", 
                        "OM Hackintosh Pci. Series Killer E2600 Ethernet Controller", 
                        "device_type", 
                        "Ethernet Controller"
                    })
                }
            }
        }
    }

    If (_OSI ("Darwin"))
    {
        Scope (\_SB)
        {
            Device (RMNE)
            {
                Name (_HID, "NULE0000")  // _HID: Hardware ID
                Name (MAC, Buffer (0x06)
                {
                     0x11, 0x22, 0x33, 0x44, 0x55, 0x66               // ."3DUf
                })
                Method (_DSM, 4, NotSerialized)  // _DSM: Device-Specific Method
                {
                    If ((Arg2 == Zero))
                    {
                        Return (Buffer (One)
                        {
                             0x03                                             // .
                        })
                    }

                    Return (Package (0x0A)
                    {
                        "built-in", 
                        Buffer (One)
                        {
                             0x00                                             // .
                        }, 

                        "IOName", 
                        "ethernet", 
                        "name", 
                        "ethernet", 
                        "model", 
                        "RM-NullEthernet-1001", 
                        "device_type", 
                        "ethernet"
                    })
                }
            }
        }
    }
}

