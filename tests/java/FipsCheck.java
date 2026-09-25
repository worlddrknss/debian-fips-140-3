// Checks that Java's cryptography runs only through Bouncy Castle FIPS.
//
//   java -jar fipscheck.jar crypto       provider and algorithm enforcement
//   java -jar fipscheck.jar tls <port>   prints the TLS cipher suite negotiated
//                                        with a local server; exits non-zero if
//                                        the handshake fails
import java.io.IOException;
import java.security.GeneralSecurityException;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.Provider;
import java.security.SecureRandom;
import java.security.Security;
import java.security.cert.X509Certificate;
import java.util.Arrays;
import java.util.List;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;

public class FipsCheck {

    private static boolean failed;

    public static void main(String[] args) throws Exception {
        if (args.length == 1 && args[0].equals("crypto")) {
            crypto();
        } else if (args.length == 2 && args[0].equals("tls")) {
            tls(Integer.parseInt(args[1]));
        } else {
            System.err.println("usage: fipscheck crypto | fipscheck tls <port>");
            System.exit(2);
        }
        System.exit(failed ? 1 : 0);
    }

    interface Check {
        Object run() throws Exception;
    }

    static void works(String label, Check check) {
        try {
            check.run();
            System.out.println("PASS: " + label + " works");
        } catch (Exception e) {
            System.err.println("FAIL: " + label + ": " + e);
            failed = true;
        }
    }

    static void rejected(String label, Check check) {
        try {
            check.run();
            System.err.println("FAIL: " + label + " succeeded");
            failed = true;
        } catch (GeneralSecurityException e) {
            System.out.println("PASS: " + label + " is rejected");
        } catch (Exception e) {
            System.err.println("FAIL: " + label + ": unexpected " + e);
            failed = true;
        }
    }

    static void crypto() throws Exception {
        List<String> providers = Arrays.stream(Security.getProviders()).map(Provider::getName).toList();
        if (!providers.equals(List.of("BCFIPS", "BCJSSE", "FIPSEntropy"))) {
            System.err.println("FAIL: providers are " + providers);
            failed = true;
        } else {
            System.out.println("PASS: providers are exactly " + providers);
        }
        if (!org.bouncycastle.crypto.CryptoServicesRegistrar.isInApprovedOnlyMode()) {
            System.err.println("FAIL: BC FIPS is not in approved-only mode");
            failed = true;
        } else {
            System.out.println("PASS: BC FIPS is in approved-only mode");
        }

        byte[] data = {1};
        works("SHA-256", () -> MessageDigest.getInstance("SHA-256").digest(data));
        works("SHA3-256", () -> MessageDigest.getInstance("SHA3-256").digest(data));
        works("AES-256-GCM", () -> {
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(new byte[32], "AES"), new GCMParameterSpec(128, new byte[12]));
            return c.doFinal(data);
        });
        works("SecureRandom (BCFIPS DRBG)", () -> {
            SecureRandom random = new SecureRandom();
            if (!random.getProvider().getName().equals("BCFIPS")) {
                throw new IllegalStateException("default SecureRandom from " + random.getProvider().getName());
            }
            return random.nextInt();
        });
        works("SecureRandom.getInstanceStrong()", () -> SecureRandom.getInstanceStrong().nextInt());
        works("default trust store", () -> {
            TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
            tmf.init((KeyStore) null);
            int anchors = ((X509TrustManager) tmf.getTrustManagers()[0]).getAcceptedIssuers().length;
            if (anchors < 100) {
                throw new IllegalStateException("only " + anchors + " trust anchors");
            }
            return anchors;
        });
        rejected("MD5", () -> MessageDigest.getInstance("MD5"));
        rejected("HMAC-MD5", () -> Mac.getInstance("HmacMD5"));
        rejected("SHA1PRNG", () -> SecureRandom.getInstance("SHA1PRNG"));
        rejected("3DES encryption", () -> {
            Cipher c = Cipher.getInstance("DESede/ECB/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(new byte[24], "DESede"));
            return c.doFinal(new byte[8]);
        });
    }

    static void tls(int port) throws Exception {
        TrustManager trustAll = new X509TrustManager() {
            public void checkClientTrusted(X509Certificate[] chain, String authType) {}
            public void checkServerTrusted(X509Certificate[] chain, String authType) {}
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
        };
        SSLContext context = SSLContext.getInstance("TLS");
        context.init(null, new TrustManager[] {trustAll}, null);
        try (SSLSocket socket = (SSLSocket) context.getSocketFactory().createSocket("127.0.0.1", port)) {
            socket.startHandshake();
            System.out.println(socket.getSession().getCipherSuite() + " " + context.getProvider().getName());
        } catch (IOException e) {
            System.err.println(e);
            failed = true;
        }
    }
}
