/*
 * Acer Nitro AN515-55 RTD3 wrapper methods for NullMoth NVRM.kext.
 *
 * macOS AppleACPIPlatform's IOACPIPlatformDevice::evaluateObject() rejects
 * path-qualified names longer than 4 characters with kIOReturnBadArgument
 * (0xe00002c2). NVRM's rtd3Acpi resolver lands on the first IOACPIPlatformDevice
 * parent of PEG0@1 in IOService, which on AN515-55 is \_SB.PCI0.
 *
 * Exposing 4-character methods NXOF and NXO_ in Scope (\_SB.PCI0) lets
 * NVRM invoke them with:
 *   boot-args: nvrtd3=1 nvrtd3off=NXOF nvrtd3on=NXO_
 *
 * OEM SSDT5.dsl implements \_SB.PCI0.PEG0.PG00._OFF and _ON (checking
 * OSYS > 0x07D9, satisfied by SSDT-XOSI.aml), including PGON(), CMDR=0x07,
 * D0ST=0, link poll on PEGP.SSSV != 0xFFFFFFFF, and SSSV restore.
 *
 * Generate binary AML without requiring iasl via:
 *   python3 build-rtd3-aml.py -o SSDT-NXRTD3.aml
 */
DefinitionBlock ("", "SSDT", 2, "ACERNI", "NXRTD3", 0x00001000)
{
    External (\_SB_.PCI0, DeviceObj)
    External (\_SB_.PCI0.PEG0.PG00._OFF, MethodObj)
    External (\_SB_.PCI0.PEG0.PG00._ON, MethodObj)

    Scope (\_SB.PCI0)
    {
        Method (NXOF, 0, Serialized)
        {
            If (CondRefOf (\_SB.PCI0.PEG0.PG00._OFF))
            {
                \_SB.PCI0.PEG0.PG00._OFF ()
            }
            Return (One)
        }

        Method (NXO_, 0, Serialized)
        {
            If (CondRefOf (\_SB.PCI0.PEG0.PG00._ON))
            {
                \_SB.PCI0.PEG0.PG00._ON ()
            }
            Return (One)
        }
    }
}
