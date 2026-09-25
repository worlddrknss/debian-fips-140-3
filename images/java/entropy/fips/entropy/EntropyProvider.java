/*
 * Supplies OS entropy to the Bouncy Castle FIPS provider.
 *
 * BC-FJA seeds its DRBG from SecureRandom.getInstanceStrong(). That normally
 * resolves to the JDK's SUN provider, but SUN also serves non-approved
 * algorithms (MD5, SHA1PRNG, ...), so keeping it installed would leave them
 * available despite approved-only mode. This provider offers exactly one
 * service, the kernel's /dev/random, so SUN can be removed. It is the approach
 * the Bouncy Castle maintainers suggest in bcgit/bc-java discussion #1910.
 *
 * Like SUN's NativePRNGBlocking, which it replaces, this sits outside the
 * BC-FJA module boundary; entropy quality is the host kernel's.
 */
package fips.entropy;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.Provider;
import java.security.SecureRandomSpi;
import java.util.Map;

public final class EntropyProvider extends Provider {

    private static final Path SOURCE = Path.of("/dev/random");

    public EntropyProvider() {
        super("FIPSEntropy", "1.0", "Kernel entropy (/dev/random) for seeding the BC FIPS DRBG");
        putService(new Service(this, "SecureRandom", "NativeEntropy",
                DevRandom.class.getName(), null, Map.of("ThreadSafe", "true")));
    }

    /** Reads directly from /dev/random. Seeding is ignored: it's an entropy source. */
    public static final class DevRandom extends SecureRandomSpi {

        public DevRandom() {
        }

        @Override
        protected void engineSetSeed(byte[] seed) {
        }

        @Override
        protected void engineNextBytes(byte[] bytes) {
            try (InputStream in = Files.newInputStream(SOURCE)) {
                int off = 0;
                while (off < bytes.length) {
                    int n = in.read(bytes, off, bytes.length - off);
                    if (n < 0) {
                        throw new IOException("unexpected end of " + SOURCE);
                    }
                    off += n;
                }
            } catch (IOException e) {
                throw new UncheckedIOException("reading " + SOURCE, e);
            }
        }

        @Override
        protected byte[] engineGenerateSeed(int numBytes) {
            byte[] seed = new byte[numBytes];
            engineNextBytes(seed);
            return seed;
        }
    }
}
