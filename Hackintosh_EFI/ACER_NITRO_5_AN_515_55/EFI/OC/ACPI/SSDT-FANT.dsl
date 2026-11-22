/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20251212 (64-bit version)
 * Copyright (c) 2000 - 2025 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of /Users/miqbalf/Documents/HACKINTOSH_EFI/EFI_20260121/OC/ACPI/SSDT-FANT.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x00000CA8 (3240)
 *     Revision         0x02
 *     Checksum         0x24
 *     OEM ID           "HACK"
 *     OEM Table ID     "FANT"
 *     OEM Revision     0x00000003 (3)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20200925 (538970405)
 */
DefinitionBlock ("", "SSDT", 2, "HACK", "FANT", 0x00000003)
{
    External (_SB_.PCI0.LPCB.EC0_, DeviceObj)
    External (_SB_.PCI0.LPCB.EC0_.CPUF, FieldUnitObj)
    External (_SB_.PCI0.LPCB.EC0_.CTMP, FieldUnitObj)
    External (_SB_.PCI0.LPCB.EC0_.FAN1, FieldUnitObj)
    External (_SB_.PCI0.LPCB.EC0_.FAN2, FieldUnitObj)
    External (_SB_.PCI0.LPCB.EC0_.FANT, FieldUnitObj)
    External (_SB_.PCI0.LPCB.EC0_.FANW, MethodObj)    // 2 Arguments
    External (_SB_.PCI0.LPCB.EC0_.GPUF, FieldUnitObj)
    External (_SB_.PCI0.LPCB.EC0_.INIT, FieldUnitObj)
    External (_SB_.PCI0.LPCB.EC0_.MODE, FieldUnitObj)
    External (_SB_.PCI0.LPCB.EC0_.OKEC, IntObj)

    Scope (\_SB)
    {
        Device (FNBT)
        {
            Name (_HID, "FANT0003")  // _HID: Hardware ID
            Name (_STA, 0x0F)  // _STA: Status
            Name (IDLE, 0x32)
            Name (MIDL, 0x50)
            Name (MAXS, 0x64)
            Name (TLOW, 0x32)
            Name (TMID, 0x50)
            Name (TMAX, 0x5F)
            Name (LSPD, Zero)
            Name (GSPD, Zero)
            Name (FMEN, Zero)
            Method (ENBL, 0, Serialized)
            {
                If (_OSI ("Darwin"))
                {
                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FAN1))
                    {
                        \_SB.PCI0.LPCB.EC0.FAN1 = Zero
                    }

                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FAN2))
                    {
                        \_SB.PCI0.LPCB.EC0.FAN2 = Zero
                    }

                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FANT))
                    {
                        \_SB.PCI0.LPCB.EC0.FANT = Zero
                    }

                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.MODE))
                    {
                        \_SB.PCI0.LPCB.EC0.MODE = Zero
                    }

                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.INIT))
                    {
                        \_SB.PCI0.LPCB.EC0.INIT = Zero
                        Sleep (0x64)
                        \_SB.PCI0.LPCB.EC0.INIT = One
                        Sleep (0x64)
                        \_SB.PCI0.LPCB.EC0.INIT = Zero
                        Sleep (0xC8)
                        \_SB.PCI0.LPCB.EC0.INIT = One
                        Sleep (0x64)
                        \_SB.PCI0.LPCB.EC0.INIT = Zero
                        Sleep (0xC8)
                    }
                    Else
                    {
                        Sleep (0x012C)
                    }

                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.MODE))
                    {
                        \_SB.PCI0.LPCB.EC0.MODE = One
                        Sleep (0x32)
                    }

                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FANT))
                    {
                        \_SB.PCI0.LPCB.EC0.FANT = One
                        Sleep (0x32)
                        \_SB.PCI0.LPCB.EC0.FANT = One
                        Sleep (0x32)
                    }

                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FAN1))
                    {
                        \_SB.PCI0.LPCB.EC0.FAN1 = One
                    }

                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FAN2))
                    {
                        \_SB.PCI0.LPCB.EC0.FAN2 = One
                    }

                    Sleep (0xC8)
                    FMEN = One
                    Return (One)
                }

                Return (Zero)
            }

            Method (DSBL, 0, Serialized)
            {
                If (_OSI ("Darwin"))
                {
                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FAN1))
                    {
                        \_SB.PCI0.LPCB.EC0.FAN1 = Zero
                    }

                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FAN2))
                    {
                        \_SB.PCI0.LPCB.EC0.FAN2 = Zero
                    }

                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FANT))
                    {
                        \_SB.PCI0.LPCB.EC0.FANT = Zero
                    }

                    FMEN = Zero
                    Return (One)
                }

                Return (Zero)
            }

            Method (CALC, 1, Serialized)
            {
                Local0 = Arg0
                If ((Local0 < TLOW))
                {
                    Return (IDLE) /* \_SB_.FNBT.IDLE */
                }

                If ((Local0 < TMID))
                {
                    Local1 = (Local0 - TLOW) /* \_SB_.FNBT.TLOW */
                    Local2 = (MIDL - IDLE) /* \_SB_.FNBT.IDLE */
                    Local3 = (TMID - TLOW) /* \_SB_.FNBT.TLOW */
                    Local4 = ((Local1 * Local2) / Local3)
                    Return ((IDLE + Local4))
                }

                If ((Local0 < TMAX))
                {
                    Local1 = (Local0 - TMID) /* \_SB_.FNBT.TMID */
                    Local2 = (MAXS - MIDL) /* \_SB_.FNBT.MIDL */
                    Local3 = (TMAX - TMID) /* \_SB_.FNBT.TMID */
                    Local4 = ((Local1 * Local2) / Local3)
                    Local5 = (MIDL + Local4)
                    If ((Local5 > MAXS))
                    {
                        Return (MAXS) /* \_SB_.FNBT.MAXS */
                    }

                    Return (Local5)
                }

                Return (MAXS) /* \_SB_.FNBT.MAXS */
            }

            Method (UFAN, 0, Serialized)
            {
                If ((FMEN == Zero))
                {
                    ENBL ()
                }

                Local0 = 0x50
                If (CondRefOf (\_SB.PCI0.LPCB.EC0.CTMP))
                {
                    Local0 = \_SB.PCI0.LPCB.EC0.CTMP /* External reference */
                }

                Local1 = CALC (Local0)
                Local2 = Local1
                If (CondRefOf (\_SB.PCI0.LPCB.EC0.CPUF))
                {
                    \_SB.PCI0.LPCB.EC0.CPUF = Local1
                    Sleep (0x14)
                    \_SB.PCI0.LPCB.EC0.CPUF = Local1
                    Sleep (0x14)
                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FANW))
                    {
                        \_SB.PCI0.LPCB.EC0.FANW (0x37, Local1)
                        Sleep (0x14)
                        \_SB.PCI0.LPCB.EC0.FANW (0x37, Local1)
                        Sleep (0x14)
                    }

                    \_SB.PCI0.LPCB.EC0.CPUF = Local1
                    Sleep (0x1E)
                }

                If (CondRefOf (\_SB.PCI0.LPCB.EC0.GPUF))
                {
                    \_SB.PCI0.LPCB.EC0.GPUF = Local2
                    Sleep (0x0A)
                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FANW))
                    {
                        \_SB.PCI0.LPCB.EC0.FANW (0x3A, Local2)
                        Sleep (0x0A)
                    }

                    \_SB.PCI0.LPCB.EC0.GPUF = Local2
                    Sleep (0x0A)
                }

                LSPD = Local1
                GSPD = Local2
                Return (Local0)
            }

            Method (_INI, 0, Serialized)  // _INI: Initialize
            {
                If (_OSI ("Darwin"))
                {
                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.MODE))
                    {
                        If ((\_SB.PCI0.LPCB.EC0.MODE == One))
                        {
                            FMEN = One
                            Return (Zero)
                        }
                    }

                    Sleep (0x1388)
                    ENBL ()
                    UFAN ()
                }
            }

            Method (GETT, 0, Serialized)
            {
                If (CondRefOf (\_SB.PCI0.LPCB.EC0.CTMP))
                {
                    Return (\_SB.PCI0.LPCB.EC0.CTMP) /* External reference */
                }

                Return (0xFF)
            }

            Method (GETS, 0, Serialized)
            {
                Return (LSPD) /* \_SB_.FNBT.LSPD */
            }

            Method (GETM, 0, Serialized)
            {
                Return (FMEN) /* \_SB_.FNBT.FMEN */
            }

            Method (GETE, 0, Serialized)
            {
                Local0 = Package (0x09)
                    {
                        0xFF, 
                        0xFF, 
                        0xFF, 
                        0xFF, 
                        0xFF, 
                        0xFF, 
                        0xFF, 
                        0xFF, 
                        0xFF
                    }
                If (CondRefOf (\_SB.PCI0.LPCB.EC0.MODE))
                {
                    Local0 [Zero] = \_SB.PCI0.LPCB.EC0.MODE /* External reference */
                }

                If (CondRefOf (\_SB.PCI0.LPCB.EC0.INIT))
                {
                    Local0 [One] = \_SB.PCI0.LPCB.EC0.INIT /* External reference */
                }

                If (CondRefOf (\_SB.PCI0.LPCB.EC0.FAN1))
                {
                    Local0 [0x02] = \_SB.PCI0.LPCB.EC0.FAN1 /* External reference */
                }

                If (CondRefOf (\_SB.PCI0.LPCB.EC0.FAN2))
                {
                    Local0 [0x03] = \_SB.PCI0.LPCB.EC0.FAN2 /* External reference */
                }

                If (CondRefOf (\_SB.PCI0.LPCB.EC0.FANT))
                {
                    Local0 [0x04] = \_SB.PCI0.LPCB.EC0.FANT /* External reference */
                }

                If (CondRefOf (\_SB.PCI0.LPCB.EC0.CPUF))
                {
                    Local0 [0x05] = \_SB.PCI0.LPCB.EC0.CPUF /* External reference */
                }

                If (CondRefOf (\_SB.PCI0.LPCB.EC0.GPUF))
                {
                    Local0 [0x06] = \_SB.PCI0.LPCB.EC0.GPUF /* External reference */
                }

                If (CondRefOf (\_SB.PCI0.LPCB.EC0.CTMP))
                {
                    Local0 [0x07] = \_SB.PCI0.LPCB.EC0.CTMP /* External reference */
                }

                If (CondRefOf (\_SB.PCI0.LPCB.EC0.OKEC))
                {
                    Local0 [0x08] = \_SB.PCI0.LPCB.EC0.OKEC /* External reference */
                }

                Return (Local0)
            }

            Method (SETS, 1, Serialized)
            {
                If ((FMEN == Zero))
                {
                    ENBL ()
                }

                Local0 = Arg0
                Local1 = Local0
                If (CondRefOf (\_SB.PCI0.LPCB.EC0.CPUF))
                {
                    \_SB.PCI0.LPCB.EC0.CPUF = Local0
                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FANW))
                    {
                        \_SB.PCI0.LPCB.EC0.FANW (0x37, Local0)
                    }
                }

                If (CondRefOf (\_SB.PCI0.LPCB.EC0.GPUF))
                {
                    \_SB.PCI0.LPCB.EC0.GPUF = Local1
                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FANW))
                    {
                        \_SB.PCI0.LPCB.EC0.FANW (0x3A, Local1)
                    }
                }

                LSPD = Local0
                GSPD = Local1
                Return (One)
            }

            Method (FORC, 0, Serialized)
            {
                Return (UFAN ())
            }

            Method (COOL, 0, Serialized)
            {
                If (_OSI ("Darwin"))
                {
                    If (CondRefOf (\_SB.PCI0.LPCB.EC0.FANT))
                    {
                        \_SB.PCI0.LPCB.EC0.FANT = One
                        Sleep (0x32)
                        \_SB.PCI0.LPCB.EC0.FANT = One
                        Sleep (0x32)
                        \_SB.PCI0.LPCB.EC0.FANT = One
                        Sleep (0x32)
                        If (CondRefOf (\_SB.PCI0.LPCB.EC0.FAN1))
                        {
                            \_SB.PCI0.LPCB.EC0.FAN1 = One
                            Sleep (0x32)
                        }
                    }

                    Return (One)
                }

                Return (Zero)
            }

            Method (_Q00, 0, Serialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                If (_OSI ("Darwin"))
                {
                    UFAN ()
                }
            }
        }

        ThermalZone (THRM)
        {
            Method (_CRT, 0, Serialized)  // _CRT: Critical Temperature
            {
                Return (0x0E94)
            }

            Method (_HOT, 0, Serialized)  // _HOT: Hot Temperature
            {
                Return (0x0E2F)
            }

            Method (_PSV, 0, Serialized)  // _PSV: Passive Temperature
            {
                Return (0x0DFD)
            }

            Method (_AC0, 0, Serialized)  // _ACx: Active Cooling, x=0-9
            {
                Return (0x0DCB)
            }

            Method (_TMP, 0, Serialized)  // _TMP: Temperature
            {
                If (_OSI ("Darwin"))
                {
                    \_SB.FNBT.COOL ()
                    Local0 = \_SB.FNBT.UFAN ()
                    Local1 = ((Local0 + 0x0111) * 0x0A)
                    Return (Local1)
                }

                Return (0x0BA5)
            }

            Name (_TZP, 0x14)  // _TZP: Thermal Zone Polling
        }
    }
}

