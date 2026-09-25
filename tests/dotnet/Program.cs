// Checks that .NET's cryptography runs through the OpenSSL FIPS provider.
//
//   fipscheck crypto       algorithm enforcement
//   fipscheck tls <port>   prints the TLS cipher suite negotiated with a local
//                          server; exits non-zero if the handshake fails
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;

return args switch
{
    ["crypto"] => Crypto(),
    ["tls", var port] => await Tls(int.Parse(port)),
    _ => Usage(),
};

static int Crypto()
{
    var failed = false;

    void Rejected(string label, Action action)
    {
        try
        {
            action();
            Console.Error.WriteLine($"FAIL: {label} succeeded");
            failed = true;
        }
        catch (CryptographicException)
        {
            Console.WriteLine($"PASS: {label} is rejected");
        }
    }

    void Works(string label, Action action)
    {
        try
        {
            action();
            Console.WriteLine($"PASS: {label} works");
        }
        catch (CryptographicException e)
        {
            Console.Error.WriteLine($"FAIL: {label}: {e.Message}");
            failed = true;
        }
    }

    var data = "x"u8.ToArray();
    Works("SHA-256", () => SHA256.HashData(data));
    Works("SHA3-256", () => SHA3_256.HashData(data));
    Works("AES-256-GCM", () =>
    {
        using var aes = new AesGcm(new byte[32], 16);
        aes.Encrypt(new byte[12], data, new byte[data.Length], new byte[16]);
    });
    Works("ECDSA P-256 sign", () => ECDsa.Create(ECCurve.NamedCurves.nistP256).SignData(data, HashAlgorithmName.SHA256));
    Rejected("MD5", () => MD5.HashData(data));
    Rejected("HMAC-MD5", () => HMACMD5.HashData(new byte[16], data));
    Rejected("3DES encryption", () =>
    {
        using var des = TripleDES.Create();
        des.Key = new byte[24];
        des.EncryptEcb(new byte[8], PaddingMode.None);
    });

    Console.WriteLine($"INFO: OpenSSL {SafeEvpPKeyHandle.OpenSslVersion:X}");
    return failed ? 1 : 0;
}

static async Task<int> Tls(int port)
{
    try
    {
        using var client = new TcpClient();
        await client.ConnectAsync("127.0.0.1", port);
        using var tls = new SslStream(client.GetStream(), false, (_, _, _, _) => true);
        await tls.AuthenticateAsClientAsync("localhost");
        Console.WriteLine(tls.NegotiatedCipherSuite);
        return 0;
    }
    catch (Exception e) when (e is AuthenticationException or IOException or SocketException)
    {
        Console.Error.WriteLine(e.Message);
        return 1;
    }
}

static int Usage()
{
    Console.Error.WriteLine("usage: fipscheck crypto | fipscheck tls <port>");
    return 2;
}
