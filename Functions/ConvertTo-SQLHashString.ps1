function ConvertTo-SQLHashString {
    #Function to convert hexadecimal to binary
    param([parameter(Mandatory = $true)] $binhash)
    $outstring = '0x'
    $binhash | ForEach-Object { $outstring += ('{0:X}' -f $_).PadLeft(2, '0') }
    return $outstring
}