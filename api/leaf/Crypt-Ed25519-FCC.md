### **📌 Ed25519FCC: Multi-Language Ed25519 Wrapper**
**A cross-platform cryptographic module for Ed25519 key generation, signing, and verification, supporting Perl-compatible 64-byte ⇄ 32-byte private key conversion.**

---

## **🔍 Overview: Ed25519 Support by Programming Language & Module**
| **Programming Language** | **Library/Module**                       | **Private Key Type**    | **Key Size** | **Notes** |
|--------------------------|-----------------------------------------|------------------------|-------------|----------|
| **Python**              | `pynacl` (libsodium), `cryptography`    | Standard              | 32 bytes    | Compatible with most languages |
| **Rust**                | `ed25519-dalek`, `ring`                 | Standard              | 32 bytes    | High-performance, Web3-friendly |
| **Go**                  | `crypto/ed25519`, `golang.org/x/crypto` | Standard              | 32 bytes    | Use `crypto/ed25519` for standard |
| **Java**                | `BouncyCastle`, `Tink`                  | Standard              | 32 bytes    | Popular for Android & enterprise apps |
| **Kotlin**              | `BouncyCastle`, `Tink`                  | Standard              | 32 bytes    | Same as Java |
| **Node.js**             | `tweetnacl`, `libsodium`                | Standard              | 32 bytes    | Used in Web3 & blockchain applications |
| **Swift (iOS)**         | `CryptoKit`                             | Standard              | 32 bytes    | Apple's native Ed25519 API |
| **C/C++**               | `libsodium`, `ed25519-donna`            | Standard              | 32 bytes    | `libsodium` is the safest choice |
| **C/C++ (alt)**         | `ref10`, `supercop`                     | Seed + PubKey         | 64 bytes    | **First 32 bytes are the private key** |
| **Perl**                | `Crypt::Ed25519`                        | Split (4-bit format)  | 64 bytes    | **Requires conversion to 32-byte format** |
| **PHP**                 | `sodium_crypto_sign_keypair()` (libsodium) | Standard          | 32 bytes    | Compatible with Python & Go |
| **Ruby**                | `RbNaCl`, `Ed25519 gem`                 | Standard              | 32 bytes    | Wrapper around `libsodium` |
| **Haskell**             | `Crypto.Sodium`                         | Seed + PubKey         | 64 bytes    | **First 32 bytes are the private key** |

---

## **📌 Key Observations**
- **Most modern languages use the 32-byte standard private key format.**
- **Perl (`Crypt::Ed25519`) uses a 64-byte 4-bit encoding**, requiring **conversion** to 32-byte format.
- **Some older C implementations** (like `ref10` and `supercop`) store the **seed + public key in 64 bytes**, but the **first 32 bytes serve as the private key**.

---

## **📖 Table of Contents**
- [Introduction](#-introduction)
- [Supported Languages](#-supported-languages)
  - [Android (Java)](#-android-java)
  - [Kotlin](#-kotlin)
  - [iOS (Swift)](#-ios-swift)
  - [JavaScript (Node.js & Browser)](#-javascript-nodejs--browser)
  - [Python](#-python)
  - [Go](#-go)
  - [Rust](#-rust)
  - [Ruby](#-ruby)
  - [OpenSSL](#-openssl)
- [How It Works](#-how-it-works)
- [Next Steps](#-next-steps)

---

## **📌 Introduction**
Ed25519FCC is a cryptographic library that provides **Ed25519 key management, signing, and verification** across multiple programming languages. It ensures **compatibility with Perl's 64-byte private key format**, making it easier to integrate Ed25519 functionality across different platforms, including **mobile, backend, and Web3 applications**.

✅ **Multi-language SDK** for cryptographic operations.  
✅ **Web3-ready** for signing blockchain transactions.  
✅ **Supports 64-byte Perl ⇄ 32-byte Standard Private Key Conversion.**  
✅ **Cross-platform:** Works on Android, iOS, Web, and Backend.  

---

## **🚀 Supported Languages**

### **📱 Android (Java)**
- Uses **BouncyCastle** for Ed25519 key generation, signing, and verification.
- Converts between **Perl-style 64-byte** and **Standard 32-byte** private keys.

📌 **[View the Android module](#-ed25519fcc-for-android)**

---

### **📱 Kotlin**
- Provides full Kotlin implementation for **Android applications**.
- Uses BouncyCastle similar to Java for keypair generation and signing.

📌 **[View the Kotlin module](#-ed25519fcc-for-kotlin)**

---

### **📱 iOS (Swift)**
- Implements **CryptoKit** for Ed25519 keypair management.
- Wrapper around Apple's native Ed25519 functions.

📌 **[View the iOS module](#-ed25519fcc-for-ios)**

---

### **🌐 JavaScript (Node.js & Browser)**
- Uses **TweetNaCl.js** for fast, efficient Ed25519 cryptography.
- Supports **both Node.js and browser environments**.

📌 **[View the JavaScript module](#-ed25519fcc-for-javascript)**

---

### **🐍 Python**
- Based on **PyNaCl (libsodium bindings)** for cryptographic operations.
- Enables signing and verification for **Python Web3 apps**.

📌 **[View the Python module](#-ed25519fcc-for-python)**

---

### **🚀 Go (Golang)**
- Uses **Go's built-in crypto/ed25519 package**.
- Lightweight and efficient for blockchain and backend apps.

📌 **[View the Go module](#-ed25519fcc-for-go)**

---

### **🦀 Rust**
- Uses **RustCrypto’s ed25519-dalek** for ultra-secure key handling.
- Ideal for **blockchain development and high-performance systems**.

📌 **[View the Rust module](#-ed25519fcc-for-rust)**

---

### **💎 Ruby**
- Built on **RbNaCl** (libsodium bindings for Ruby).
- Enables signing and verifying messages for **Rails & Web3 apps**.

📌 **[View the Ruby module](#-ed25519fcc-for-ruby)**

---

### **🌐 OpenSSL**

📌 **[View the OpenSSL module](#-ed25519fcc-for-openssl)**

---

## **🛠️ How It Works**
1. **Key Generation**:  
   - Each module generates a **64-byte Perl-style private key** and a **32-byte public key**.  

2. **Private Key Conversion**:  
   - The module provides functions to **convert between 64-byte and 32-byte private keys**.

3. **Signing & Verification**:  
   - Messages are **signed** with the 64-byte Perl key (converted to 32-byte).  
   - **Verification** is done using the public key.

---

## **🚀 Next Steps**
🔹 **Choose your language and integrate Ed25519FCC** into your application.  
🔹 **Test cross-platform compatibility** by signing in one language and verifying in another.  
🔹 **Deploy your application** to Web3, blockchain, or secure backend environments.  

📌 **Ed25519FCC ensures cross-platform security and flexibility for cryptographic signing and verification in modern applications.** 🚀  

---



# Factorial-Cryptographic-Converter

FactorialCoin Ed25519 `Private Key` Compatibility Wrapper

All a wallet and a miner application interacts with is this wrapper class to work with Ed25519.

---

## Core Perl Conversion

```perl
package Crypt::Ed25519::FCC;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    private_key_32
    private_key_64
);

# Converteer een 64-byte Perl private key naar een 32-byte standaard private key
sub private_key_32 {
    my ($privkey64) = @_;
    die "Ongeldige Perl private key lengte" unless length($privkey64) == 64;
    
    my @e;
    for my $i (0 .. 31) {
        $e[$i] = (ord(substr($privkey64, 2 * $i, 1)) & 15) | ((ord(substr($privkey64, 2 * $i + 1, 1)) & 15) << 4);
    }
    return pack("C32", @e);
}

# Converteer een 32-byte standaard private key naar een 64-byte Perl private key
sub private_key_64 {
    my ($privkey32) = @_;
    die "Ongeldige standaard private key lengte" unless length($privkey32) == 32;
    
    my @e;
    for my $i (0 .. 31) {
        $e[2 * $i] = (ord(substr($privkey32, $i, 1)) >> 0) & 15;
        $e[2 * $i + 1] = (ord(substr($privkey32, $i, 1)) >> 4) & 15;
    }
    return pack("C64", @e);
}

1;
```


---


# **📌 Ed25519FCC for Android**
A wrapper for **Ed25519 cryptography** in Android using **BouncyCastle**, supporting **64-byte ⇄ 32-byte private key conversion**.

## Android Module

```java
package nl.factorialcoin.Ed25519FCC;

import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters;
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters;
import org.bouncycastle.crypto.signers.Ed25519Signer;
import java.security.SecureRandom;

public class Ed25519FCC {

    // Convert 64-byte Perl private key to 32-byte standard private key
    private static byte[] privateKey32(byte[] privkey64) {
        if (privkey64.length != 64) {
            throw new IllegalArgumentException("Invalid Perl private key length");
        }
        byte[] privkey32 = new byte[32];
        for (int i = 0; i < 32; i++) {
            privkey32[i] = (byte) ((privkey64[2 * i] & 0x0F) | ((privkey64[2 * i + 1] & 0x0F) << 4));
        }
        return privkey32;
    }

    // Convert 32-byte standard private key to 64-byte Perl private key
    private static byte[] privateKey64(byte[] privkey32) {
        if (privkey32.length != 32) {
            throw new IllegalArgumentException("Invalid standard private key length");
        }
        byte[] privkey64 = new byte[64];
        for (int i = 0; i < 32; i++) {
            privkey64[2 * i] = (byte) ((privkey32[i] >> 0) & 0x0F);
            privkey64[2 * i + 1] = (byte) ((privkey32[i] >> 4) & 0x0F);
        }
        return privkey64;
    }

    // -------------------------------------------------------------------------------------------- //

    // Simple KeyPair class
    public static class KeyPair {
        public final byte[] privateKey;
        public final byte[] publicKey;
        public KeyPair(byte[] privateKey, byte[] publicKey) {
            this.privateKey = privateKey;
            this.publicKey = publicKey;
        }
    }

    // -------------------------------------------------------------------------------------------- //

    // Generate Ed25519 Keypair
    public static KeyPair generateKeypair() {
        SecureRandom random = new SecureRandom();
        Ed25519PrivateKeyParameters privateKey = new Ed25519PrivateKeyParameters(random);
        Ed25519PublicKeyParameters publicKey = privateKey.generatePublicKey();
        return new KeyPair(privateKey64(privateKey.getEncoded()), publicKey.getEncoded());
    }

    // Sign a message with a standard Ed25519 private key
    public static byte[] signMessage(byte[] perlPrivateKey, byte[] message) {
        byte[] privateKey = privateKey32(perlPrivateKey);
        Ed25519PrivateKeyParameters privateKeyParams = new Ed25519PrivateKeyParameters(privateKey, 0);
        Ed25519Signer signer = new Ed25519Signer();
        signer.init(true, privateKeyParams);
        signer.update(message, 0, message.length);
        return signer.generateSignature();
    }

    // Verify a signature with a standard Ed25519 public key
    public static boolean verifySignature(byte[] publicKey, byte[] message, byte[] signature) {
        Ed25519PublicKeyParameters publicKeyParams = new Ed25519PublicKeyParameters(publicKey, 0);
        Ed25519Signer verifier = new Ed25519Signer();
        verifier.init(false, publicKeyParams);
        verifier.update(message, 0, message.length);
        return verifier.verifySignature(signature);
    }

}
```

## **Example Usage in Android (Java)**

```java
import nl.factorialcoin.Ed25519FCC.Ed25519FCC;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

public class Main {
    public static void main(String[] args) {
        // Generate Keypair
        Ed25519FCC.KeyPair keyPair = Ed25519FCC.generateKeypair();
        System.out.println("Private Key (64-byte Perl format): " + Base64.getEncoder().encodeToString(keyPair.privateKey));
        System.out.println("Public Key: " + Base64.getEncoder().encodeToString(keyPair.publicKey));

        // Message to sign
        byte[] message = "Hello, FactorialCoin!".getBytes(StandardCharsets.UTF_8);

        // Sign the message
        byte[] signature = Ed25519FCC.signMessage(keyPair.privateKey, message);
        System.out.println("Signature: " + Base64.getEncoder().encodeToString(signature));

        // Verify the signature
        boolean isValid = Ed25519FCC.verifySignature(keyPair.publicKey, message, signature);
        System.out.println("Signature Valid: " + isValid);
    }
}
```

## **How It Works**
1. **Key Generation**  
   - Calls `generateKeypair()`, returning a **64-byte Perl-style private key** and **32-byte public key**.
   
2. **Signing**  
   - Converts **64-byte private key** to **32-byte standard key** (`privateKey32()`).
   - Signs the message using **BouncyCastle's `Ed25519Signer`**.
   
3. **Verification**  
   - Uses `Ed25519Signer` to verify the **message signature** against the public key.

## **Installation Instructions**
- Add **BouncyCastle** dependency:
```gradle
dependencies {
    implementation 'org.bouncycastle:bcprov-jdk15to18:1.70'
}
```

## **Features**
✅ **Android & Java Compatible**  
✅ **Ed25519 Keypair Generation**  
✅ **Signing & Verification**  
✅ **Supports 64-byte Perl ⇄ 32-byte Standard Private Key Conversion**  

**Now your Android app can use Ed25519 with Perl-compatible private keys!**


---


# **Ed25519FCC for Kotlin**
A Kotlin wrapper for **Ed25519 cryptography**, supporting **64-byte Perl ⇄ 32-byte Standard Private Key Conversion**.

### **Kotlin Code Implementation**
```java
package nl.factorialcoin.Ed25519FCC

import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import java.security.SecureRandom

object Ed25519FCC {

    // Convert 64-byte Perl private key to 32-byte standard private key
    private fun privateKey32(privkey64: ByteArray): ByteArray {
        require(privkey64.size == 64) { "Invalid Perl private key length" }
        val privkey32 = ByteArray(32)
        for (i in 0 until 32) {
            privkey32[i] = ((privkey64[2 * i].toInt() and 0x0F) or ((privkey64[2 * i + 1].toInt() and 0x0F) shl 4)).toByte()
        }
        return privkey32
    }

    // Convert 32-byte standard private key to 64-byte Perl private key
    private fun privateKey64(privkey32: ByteArray): ByteArray {
        require(privkey32.size == 32) { "Invalid standard private key length" }
        val privkey64 = ByteArray(64)
        for (i in 0 until 32) {
            privkey64[2 * i] = ((privkey32[i].toInt() shr 0) and 0x0F).toByte()
            privkey64[2 * i + 1] = ((privkey32[i].toInt() shr 4) and 0x0F).toByte()
        }
        return privkey64
    }

    // -------------------------------------------------------------------------------------------- //

    // Simple KeyPair data class
    data class KeyPair(val privateKey: ByteArray, val publicKey: ByteArray)

    // -------------------------------------------------------------------------------------------- //

    // Generate Ed25519 Keypair
    fun generateKeypair(): KeyPair {
        val random = SecureRandom()
        val privateKey = Ed25519PrivateKeyParameters(random)
        val publicKey = privateKey.generatePublicKey()
        return KeyPair(privateKey64(privateKey.encoded), publicKey.encoded)
    }

    // Sign a message with a standard Ed25519 private key
    fun signMessage(perlPrivateKey: ByteArray, message: ByteArray): ByteArray {
        val privateKey = privateKey32(perlPrivateKey)
        val privateKeyParams = Ed25519PrivateKeyParameters(privateKey, 0)
        val signer = Ed25519Signer()
        signer.init(true, privateKeyParams)
        signer.update(message, 0, message.size)
        return signer.generateSignature()
    }

    // Verify a signature with a standard Ed25519 public key
    fun verifySignature(publicKey: ByteArray, message: ByteArray, signature: ByteArray): Boolean {
        val publicKeyParams = Ed25519PublicKeyParameters(publicKey, 0)
        val verifier = Ed25519Signer()
        verifier.init(false, publicKeyParams)
        verifier.update(message, 0, message.size)
        return verifier.verifySignature(signature)
    }
}
```

## **Example Usage in Kotlin (Android)**
```java
import nl.factorialcoin.Ed25519FCC.Ed25519FCC
import java.util.Base64

fun main() {
    // Generate Keypair
    val keyPair = Ed25519FCC.generateKeypair()
    println("Private Key (64-byte Perl format): " + Base64.getEncoder().encodeToString(keyPair.privateKey))
    println("Public Key: " + Base64.getEncoder().encodeToString(keyPair.publicKey))

    // Message to sign
    val message = "Hello, FactorialCoin!".toByteArray()

    // Sign the message
    val signature = Ed25519FCC.signMessage(keyPair.privateKey, message)
    println("Signature: " + Base64.getEncoder().encodeToString(signature))

    // Verify the signature
    val isValid = Ed25519FCC.verifySignature(keyPair.publicKey, message, signature)
    println("Signature Valid: $isValid")
}
```

## **Installation Instructions**
- Add **BouncyCastle** dependency to your **Android `build.gradle.kts`**:
```java
dependencies {
    implementation("org.bouncycastle:bcprov-jdk15to18:1.70")
}
```

## **Features**
✅ **Kotlin & Android Compatible**  
✅ **Ed25519 Keypair Generation**  
✅ **Signing & Verification**  
✅ **Supports 64-byte Perl ⇄ 32-byte Standard Private Key Conversion**  

**Now your Kotlin/Android app can use Ed25519 with Perl-compatible private keys!**


---


# **Ed25519FCC for iOS**
A wrapper for **Ed25519 cryptography** in iOS using **Libsodium**, supporting **64-byte ⇄ 32-byte private key conversion**.

## **Swift Implementation**
```java
import Foundation
import Sodium

public struct Ed25519FCC {

    // Convert 64-byte Perl private key to 32-byte standard private key
    private static func privateKey32(from privkey64: Data) -> Data {
        guard privkey64.count == 64 else {
            fatalError("Invalid Perl private key length")
        }
        var privkey32 = Data(repeating: 0, count: 32)
        for i in 0..<32 {
            privkey32[i] = (privkey64[2 * i] & 0x0F) | ((privkey64[2 * i + 1] & 0x0F) << 4)
        }
        return privkey32
    }

    // Convert 32-byte standard private key to 64-byte Perl private key
    private static func privateKey64(from privkey32: Data) -> Data {
        guard privkey32.count == 32 else {
            fatalError("Invalid standard private key length")
        }
        var privkey64 = Data(repeating: 0, count: 64)
        for i in 0..<32 {
            privkey64[2 * i] = (privkey32[i] >> 0) & 0x0F
            privkey64[2 * i + 1] = (privkey32[i] >> 4) & 0x0F
        }
        return privkey64
    }

    // -------------------------------------------------------------------------------------------- //

    public struct KeyPair {
        public let privateKey: Data
        public let publicKey: Data
    }

    // -------------------------------------------------------------------------------------------- //

    // Generate Ed25519 Keypair
    public static func generateKeypair() -> KeyPair {
        guard let keyPair = Sodium().sign.keyPair() else {
            fatalError("Failed to generate keypair")
        }
        return KeyPair(privateKey: privateKey64(from: keyPair.secretKey), publicKey: keyPair.publicKey)
    }

    // Sign a message with a 64-byte Perl private key
    public static func signMessage(privateKey: Data, message: Data) -> Data? {
        let privKey32 = privateKey32(from: privateKey)
        return Sodium().sign.signature(message: message, secretKey: privKey32)
    }

    // Verify a signature with a standard Ed25519 public key
    public static func verifySignature(publicKey: Data, message: Data, signature: Data) -> Bool {
        return Sodium().sign.verify(message: message, publicKey: publicKey, signature: signature)
    }
}
```

## **Example Usage in Swift**
```java
import Foundation

// Generate a new keypair
let keypair = Ed25519FCC.generateKeypair()
print("Private Key (64-byte Perl format): \(keypair.privateKey.base64EncodedString())")
print("Public Key: \(keypair.publicKey.base64EncodedString())")

// Message to sign
let message = "Hello, FactorialCoin!".data(using: .utf8)!

// Sign the message
if let signature = Ed25519FCC.signMessage(privateKey: keypair.privateKey, message: message) {
    print("Signature: \(signature.base64EncodedString())")

    // Verify the signature
    let isValid = Ed25519FCC.verifySignature(publicKey: keypair.publicKey, message: message, signature: signature)
    print("Signature Valid: \(isValid)")
} else {
    print("Signing failed!")
}
```

## **Installation Instructions**
1. **Add Libsodium to Your Project**
   - **Using CocoaPods**  
     Add the following to your `Podfile`:
```sh
pod 'Sodium', '~> 1.0'
```
     Then run:
```sh
pod install
```

   - **Using Swift Package Manager (SPM)**
     Add **Sodium** as a package dependency in **Xcode**:
     - Go to `File` → `Swift Packages` → `Add Package Dependency`
     - Enter: `https://github.com/jedisct1/swift-sodium`
     - Select the latest stable version and add it to your project.

2. **Import the Module**
```swift
import Ed25519FCC
```

## **Features**
| Feature | Supported |
|------------------|------------------|
| **iOS Support** | ✅ iOS 10+ |
| **Ed25519 Keypair Generation** | ✅ Yes |
| **Message Signing** | ✅ Yes |
| **Signature Verification** | ✅ Yes |
| **64-byte Perl Private Key Support** | ✅ Yes |
| **32-byte Standard Private Key Support** | ✅ Yes |

**Now your iOS app can use Ed25519 with Perl-compatible private keys!**


---

## **Ed25519FCC for Javascript**
A **JavaScript version** of your `Ed25519FCC` wrapper
Compatible with both **Node.js and Browsers** using the **TweetNaCl.js** library.

### **Ed25519FCC.js (NodeJS & Browser)**
```javascript
import nacl from "tweetnacl";

class Ed25519FCC {
    
    // Convert 64-byte Perl private key to 32-byte standard private key
    static privateKey32(privkey64) {
        if (privkey64.length !== 64) {
            throw new Error("Invalid Perl private key length");
        }
        let privkey32 = new Uint8Array(32);
        for (let i = 0; i < 32; i++) {
            privkey32[i] = (privkey64[2 * i] & 0x0F) | ((privkey64[2 * i + 1] & 0x0F) << 4);
        }
        return privkey32;
    }

    // Convert 32-byte standard private key to 64-byte Perl private key
    static privateKey64(privkey32) {
        if (privkey32.length !== 32) {
            throw new Error("Invalid standard private key length");
        }
        let privkey64 = new Uint8Array(64);
        for (let i = 0; i < 32; i++) {
            privkey64[2 * i] = (privkey32[i] >> 0) & 0x0F;
            privkey64[2 * i + 1] = (privkey32[i] >> 4) & 0x0F;
        }
        return privkey64;
    }

    // Generate Ed25519 Keypair
    static generateKeypair() {
        const keypair = nacl.sign.keyPair();
        return {
            privateKey: Ed25519FCC.privateKey64(keypair.secretKey.slice(0, 32)), // Convert to Perl-style 64-byte key
            publicKey: keypair.publicKey
        };
    }

    // Sign a message
    static signMessage(perlPrivateKey, message) {
        const privateKey = Ed25519FCC.privateKey32(perlPrivateKey);
        return nacl.sign.detached(message, privateKey);
    }

    // Verify a signature
    static verifySignature(publicKey, message, signature) {
        return nacl.sign.detached.verify(message, signature, publicKey);
    }
}

// Export for Node.js
export default Ed25519FCC;
```

### **How to Use (NodeJS)**
```javascript
import Ed25519FCC from './Ed25519FCC.js';
import { randomBytes } from 'crypto';

const keypair = Ed25519FCC.generateKeypair();
console.log("Private Key (64-byte Perl format):", Buffer.from(keypair.privateKey).toString('hex'));
console.log("Public Key:", Buffer.from(keypair.publicKey).toString('hex'));

const message = new TextEncoder().encode("Hello, FactorialCoin!");
const signature = Ed25519FCC.signMessage(keypair.privateKey, message);

console.log("Signature:", Buffer.from(signature).toString('hex'));

const isValid = Ed25519FCC.verifySignature(keypair.publicKey, message, signature);
console.log("Signature Valid:", isValid);
```

### **How to Use (Browser)**
1. Include TweetNaCl.js from a CDN:
```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/tweetnacl/1.0.3/nacl.min.js"></script>
<script type="module">
    import Ed25519FCC from './Ed25519FCC.js';

    const keypair = Ed25519FCC.generateKeypair();
    console.log("Private Key (64-byte Perl format):", keypair.privateKey);
    console.log("Public Key:", keypair.publicKey);

    const message = new TextEncoder().encode("Hello, FactorialCoin!");
    const signature = Ed25519FCC.signMessage(keypair.privateKey, message);

    console.log("Signature:", signature);

    const isValid = Ed25519FCC.verifySignature(keypair.publicKey, message, signature);
    console.log("Signature Valid:", isValid);
</script>
```

### **Dependencies**
You'll need **TweetNaCl.js**, a fast and secure Ed25519 implementation:
- **For Node.js**: Install via `npm install tweetnacl`
- **For Browsers**: Load `tweetnacl.min.js` from a CDN like [cdnjs](https://cdnjs.com/libraries/tweetnacl).

### **Features**
- **Works in Node.js & Browsers** 🌍
- Uses **TweetNaCl.js** (a fast & secure Ed25519 implementation).
- Includes **64-byte ⇄ 32-byte private key conversion**.
- Supports **Key Generation, Signing, and Verification**.
- **No external dependencies** other than TweetNaCl.


---


# **Ed25519FCC for Rust**
Implementing Ed25519 key generation, signing, verification, and **64-byte <-> 32-byte private key conversion**.

## **Rust Code: `ed25519_fcc.rs`**
```rust
use ed25519_dalek::{Keypair, PublicKey, SecretKey, Signature, Signer, Verifier};
use rand::rngs::OsRng;

/// Convert a 64-byte Perl private key to a 32-byte standard private key
pub fn private_key_32(privkey64: &[u8]) -> Result<[u8; 32], &'static str> {
    if privkey64.len() != 64 {
        return Err("Invalid 64-byte private key length");
    }
    let mut privkey32 = [0u8; 32];
    for i in 0..32 {
        privkey32[i] = (privkey64[2 * i] & 0x0F) | ((privkey64[2 * i + 1] & 0x0F) << 4);
    }
    Ok(privkey32)
}

/// Convert a 32-byte standard private key to a 64-byte Perl private key
pub fn private_key_64(privkey32: &[u8]) -> Result<[u8; 64], &'static str> {
    if privkey32.len() != 32 {
        return Err("Invalid 32-byte private key length");
    }
    let mut privkey64 = [0u8; 64];
    for i in 0..32 {
        privkey64[2 * i] = (privkey32[i] >> 0) & 0x0F;
        privkey64[2 * i + 1] = (privkey32[i] >> 4) & 0x0F;
    }
    Ok(privkey64)
}

/// Generate an Ed25519 keypair
pub fn generate_keypair() -> (Vec<u8>, Vec<u8>) {
    let mut csprng = OsRng;
    let keypair = Keypair::generate(&mut csprng);
    let pubkey = keypair.public.to_bytes().to_vec();
    let privkey = private_key_64(&keypair.secret.to_bytes()).expect("Failed to convert key");
    (privkey, pubkey)
}

/// Sign a message with a 64-byte Perl-style private key
pub fn sign_message(privkey64: &[u8], message: &[u8]) -> Result<Vec<u8>, &'static str> {
    let privkey32 = private_key_32(privkey64)?;
    let secret = SecretKey::from_bytes(&privkey32).map_err(|_| "Invalid secret key")?;
    let public = PublicKey::from(&secret);
    let keypair = Keypair { secret, public };

    let signature = keypair.sign(message);
    Ok(signature.to_bytes().to_vec())
}

/// Verify a signature with a 32-byte public key
pub fn verify_signature(pubkey: &[u8], message: &[u8], signature: &[u8]) -> bool {
    if pubkey.len() != 32 || signature.len() != 64 {
        return false;
    }
    let public = match PublicKey::from_bytes(pubkey) {
        Ok(p) => p,
        Err(_) => return false,
    };
    let signature = match Signature::from_bytes(signature) {
        Ok(s) => s,
        Err(_) => return false,
    };
    public.verify(message, &signature).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_generation() {
        let (privkey, pubkey) = generate_keypair();
        assert_eq!(privkey.len(), 64);
        assert_eq!(pubkey.len(), 32);
    }

    #[test]
    fn test_sign_and_verify() {
        let (privkey, pubkey) = generate_keypair();
        let message = b"Hello, Rust!";
        let signature = sign_message(&privkey, message).expect("Failed to sign");
        assert!(verify_signature(&pubkey, message, &signature));
    }

    #[test]
    fn test_conversion() {
        let (privkey64, _) = generate_keypair();
        let privkey32 = private_key_32(&privkey64).expect("Conversion to 32 failed");
        let privkey64_back = private_key_64(&privkey32).expect("Conversion back to 64 failed");
        assert_eq!(privkey64, privkey64_back);
    }
}
```

## **How to Use the Rust Module**
### **1️⃣ Add Dependencies**
Add the required library to your `Cargo.toml`:
```toml
[dependencies]
ed25519-dalek = "1.0.1"
rand = "0.8"
```

### **2️⃣ Example Usage**
```rust
use ed25519_fcc::{generate_keypair, sign_message, verify_signature};

fn main() {
    // Generate Keypair
    let (privkey, pubkey) = generate_keypair();
    println!("Private Key (64-byte Perl format): {:?}", privkey);
    println!("Public Key: {:?}", pubkey);

    // Message to sign
    let message = b"Hello, FactorialCoin!";

    // Sign the message
    let signature = sign_message(&privkey, message).expect("Failed to sign");
    println!("Signature: {:?}", signature);

    // Verify the signature
    let is_valid = verify_signature(&pubkey, message, &signature);
    println!("Signature Valid: {}", is_valid);
}
```

## **Summary**
| Feature                 | Supported |
|-------------------------|----------|
| ✅ **Ed25519 Key Generation** | ✅ Yes |
| ✅ **64-byte ⇄ 32-byte Private Key Conversion** | ✅ Yes |
| ✅ **Message Signing** | ✅ Yes |
| ✅ **Signature Verification** | ✅ Yes |
| ✅ **Unit Tests Included** | ✅ Yes |

**This Rust module is ready for Web3 wallets, blockchain apps, and crypto miners!**


---


# **Ed25519FCC for Go**
Golang implementing **Ed25519 key generation, signing, verification, and 64-byte ⇄ 32-byte private key conversion**.

## **Go Code: `ed25519_fcc.go`**
```go
package ed25519fcc

import (
    "bytes"
    "crypto/ed25519"
    "crypto/rand"
    "errors"
)

// Convert 64-byte Perl private key to 32-byte standard private key
func PrivateKey32(privkey64 []byte) ([]byte, error) {
    if len(privkey64) != 64 {
        return nil, errors.New("invalid 64-byte private key length")
    }
    privkey32 := make([]byte, 32)
    for i := 0; i < 32; i++ {
        privkey32[i] = (privkey64[2*i] & 0x0F) | ((privkey64[2*i+1] & 0x0F) << 4)
    }
    return privkey32, nil
}

// Convert 32-byte standard private key to 64-byte Perl private key
func PrivateKey64(privkey32 []byte) ([]byte, error) {
    if len(privkey32) != 32 {
        return nil, errors.New("invalid 32-byte private key length")
    }
    privkey64 := make([]byte, 64)
    for i := 0; i < 32; i++ {
        privkey64[2*i] = (privkey32[i] >> 0) & 0x0F
        privkey64[2*i+1] = (privkey32[i] >> 4) & 0x0F
    }
    return privkey64, nil
}

// Generate Ed25519 Keypair
func GenerateKeypair() ([]byte, []byte, error) {
    pubKey, privKey, err := ed25519.GenerateKey(rand.Reader)
    if err != nil {
        return nil, nil, err
    }

    privKey64, err := PrivateKey64(privKey.Seed())
    if err != nil {
        return nil, nil, err
    }

    return privKey64, pubKey, nil
}

// Sign a message using a 64-byte Perl-style private key
func SignMessage(privKey64, message []byte) ([]byte, error) {
    privKey32, err := PrivateKey32(privKey64)
    if err != nil {
        return nil, err
    }
    privKey := ed25519.NewKeyFromSeed(privKey32)
    signature := privKey.Sign(nil, message)
    return signature, nil
}

// Verify a signature using a 32-byte public key
func VerifySignature(pubKey, message, signature []byte) bool {
    if len(pubKey) != ed25519.PublicKeySize || len(signature) != ed25519.SignatureSize {
        return false
    }
    return ed25519.Verify(pubKey, message, signature)
}

// Self-checks with tests
func SelfTest() error {
    // Generate keys
    privKey64, pubKey, err := GenerateKeypair()
    if err != nil {
        return err
    }

    // Message to sign
    message := []byte("Hello, Go!")

    // Sign message
    signature, err := SignMessage(privKey64, message)
    if err != nil {
        return err
    }

    // Verify signature
    if !VerifySignature(pubKey, message, signature) {
        return errors.New("signature verification failed")
    }

    // Validate key conversions
    privKey32, err := PrivateKey32(privKey64)
    if err != nil {
        return err
    }
    privKey64Back, err := PrivateKey64(privKey32)
    if err != nil {
        return err
    }
    if !bytes.Equal(privKey64, privKey64Back) {
        return errors.New("private key conversion mismatch")
    }

    return nil
}
```

## **Example Usage:**
### **1️⃣ Install Go Modules**
```sh
go mod init example.com/ed25519fcc
go get golang.org/x/crypto/ed25519
```

### **2️⃣ Example `main.go`**
```go
package main

import (
    "encoding/hex"
    "fmt"
    "log"

    "example.com/ed25519fcc"
)

func main() {
    // Generate Keypair
    privKey, pubKey, err := ed25519fcc.GenerateKeypair()
    if err != nil {
        log.Fatal("Error generating keypair:", err)
    }

    fmt.Println("Private Key (64-byte Perl format):", hex.EncodeToString(privKey))
    fmt.Println("Public Key:", hex.EncodeToString(pubKey))

    // Message to sign
    message := []byte("Hello, Go Ed25519!")

    // Sign message
    signature, err := ed25519fcc.SignMessage(privKey, message)
    if err != nil {
        log.Fatal("Error signing message:", err)
    }

    fmt.Println("Signature:", hex.EncodeToString(signature))

    // Verify the signature
    isValid := ed25519fcc.VerifySignature(pubKey, message, signature)
    fmt.Println("Signature Valid:", isValid)
}
```

## **Summary**
| Feature                 | Supported |
|-------------------------|----------|
| ✅ **Go-native Ed25519 support** | ✅ Yes |
| ✅ **64-byte ⇄ 32-byte Private Key Conversion** | ✅ Yes |
| ✅ **Ed25519 Keypair Generation** | ✅ Yes |
| ✅ **Message Signing** | ✅ Yes |
| ✅ **Signature Verification** | ✅ Yes |
| ✅ **Self-test Included** | ✅ Yes |

**This Go module is ready for Web3 wallets, blockchain applications, and crypto miners!**



---


# **Ed25519FCC for Python**
A wrapper for **Ed25519 cryptography** in Python using **PyNaCl**, supporting **64-byte ⇄ 32-byte private key conversion**.

## **Python Implementation**
```python
import nacl.signing
import nacl.encoding

class Ed25519FCC:

    @staticmethod
    def private_key_32(privkey64: bytes) -> bytes:
        """Convert 64-byte Perl private key to 32-byte standard private key."""
        if len(privkey64) != 64:
            raise ValueError("Invalid Perl private key length")
        
        privkey32 = bytearray(32)
        for i in range(32):
            privkey32[i] = (privkey64[2 * i] & 0x0F) | ((privkey64[2 * i + 1] & 0x0F) << 4)
        return bytes(privkey32)

    @staticmethod
    def private_key_64(privkey32: bytes) -> bytes:
        """Convert 32-byte standard private key to 64-byte Perl private key."""
        if len(privkey32) != 32:
            raise ValueError("Invalid standard private key length")
        
        privkey64 = bytearray(64)
        for i in range(32):
            privkey64[2 * i] = (privkey32[i] >> 0) & 0x0F
            privkey64[2 * i + 1] = (privkey32[i] >> 4) & 0x0F
        return bytes(privkey64)

    # -------------------------------------------------------------------------------------------- #

    class KeyPair:
        """Simple KeyPair class."""
        def __init__(self, private_key: bytes, public_key: bytes):
            self.private_key = private_key
            self.public_key = public_key

    # -------------------------------------------------------------------------------------------- #

    @staticmethod
    def generate_keypair() -> "Ed25519FCC.KeyPair":
        """Generate Ed25519 keypair."""
        signing_key = nacl.signing.SigningKey.generate()
        verifying_key = signing_key.verify_key
        return Ed25519FCC.KeyPair(
            Ed25519FCC.private_key_64(signing_key.encode()), 
            verifying_key.encode()
        )

    @staticmethod
    def sign_message(private_key: bytes, message: bytes) -> bytes:
        """Sign a message with a 64-byte Perl private key."""
        privkey32 = Ed25519FCC.private_key_32(private_key)
        signing_key = nacl.signing.SigningKey(privkey32)
        return signing_key.sign(message).signature

    @staticmethod
    def verify_signature(public_key: bytes, message: bytes, signature: bytes) -> bool:
        """Verify a signature with a standard Ed25519 public key."""
        verifying_key = nacl.signing.VerifyKey(public_key)
        try:
            verifying_key.verify(message, signature)
            return True
        except nacl.exceptions.BadSignatureError:
            return False
```

## **Example Usage in Python**
```python
import base64
from Ed25519FCC import Ed25519FCC

# Generate a new keypair
keypair = Ed25519FCC.generate_keypair()
print("Private Key (64-byte Perl format):", base64.b64encode(keypair.private_key).decode())
print("Public Key:", base64.b64encode(keypair.public_key).decode())

# Message to sign
message = b"Hello, FactorialCoin!"

# Sign the message
signature = Ed25519FCC.sign_message(keypair.private_key, message)
print("Signature:", base64.b64encode(signature).decode())

# Verify the signature
is_valid = Ed25519FCC.verify_signature(keypair.public_key, message, signature)
print("Signature Valid:", is_valid)
```

## **Installation Instructions**
1. **Install PyNaCl (Libsodium Wrapper for Python)**
   ```sh
   pip install pynacl
   ```
   
2. **Import the Module**
   ```python
   from Ed25519FCC import Ed25519FCC
   ```

## **Features**
| Feature | Supported |
|------------------|------------------|
| **Python 3+ Support** | ✅ Yes |
| **Ed25519 Keypair Generation** | ✅ Yes |
| **Message Signing** | ✅ Yes |
| **Signature Verification** | ✅ Yes |
| **64-byte Perl Private Key Support** | ✅ Yes |
| **32-byte Standard Private Key Support** | ✅ Yes |

**Now your Python applications can use Ed25519 with Perl-compatible private keys!**


---



# **Ed25519FCC for Ruby**
A Wrapper for **Ed25519 key generation, signing, verification, and 64-byte ⇄ 32-byte private key conversion**, using the `rbnacl` gem (libsodium-based).

## **Ruby Code: `ed25519_fcc.rb`**
```ruby
require 'rbnacl'
require 'base64'

module Ed25519FCC
  # Convert 64-byte Perl private key to 32-byte standard private key
  def self.private_key_32(privkey64)
    raise 'Invalid 64-byte private key length' unless privkey64.bytesize == 64

    privkey32 = (0...32).map do |i|
      (privkey64[2 * i].ord & 0x0F) | ((privkey64[2 * i + 1].ord & 0x0F) << 4)
    end
    privkey32.pack('C*')
  end

  # Convert 32-byte standard private key to 64-byte Perl private key
  def self.private_key_64(privkey32)
    raise 'Invalid 32-byte private key length' unless privkey32.bytesize == 32

    privkey64 = (0...32).flat_map do |i|
      [
        (privkey32[i].ord >> 0) & 0x0F,
        (privkey32[i].ord >> 4) & 0x0F
      ]
    end
    privkey64.pack('C*')
  end

  # Generate Ed25519 Keypair
  def self.generate_keypair
    seed = RbNaCl::Random.random_bytes(32)
    signing_key = RbNaCl::SigningKey.new(seed)
    public_key = signing_key.verify_key.to_bytes
    private_key_64 = private_key_64(seed)
    { private_key: private_key_64, public_key: public_key }
  end

  # Sign a message using a 64-byte Perl-style private key
  def self.sign_message(privkey64, message)
    privkey32 = private_key_32(privkey64)
    signing_key = RbNaCl::SigningKey.new(privkey32)
    signing_key.sign(message)
  end

  # Verify a signature using a 32-byte public key
  def self.verify_signature(pubkey, message, signature)
    verify_key = RbNaCl::VerifyKey.new(pubkey)
    verify_key.verify(signature, message)
  rescue RbNaCl::BadSignatureError
    false
  end

  # Self-test function
  def self.self_test
    keypair = generate_keypair
    message = 'Hello, Ruby Ed25519!'

    # Sign the message
    signature = sign_message(keypair[:private_key], message)

    # Verify the signature
    valid = verify_signature(keypair[:public_key], message, signature)

    # Validate key conversion
    privkey32 = private_key_32(keypair[:private_key])
    privkey64_back = private_key_64(privkey32)

    raise 'Signature verification failed' unless valid
    raise 'Private key conversion mismatch' unless privkey64_back == keypair[:private_key]

    puts 'Self-test passed!'
  end
end
```

---

## **Example Usage**
### **1️⃣ Install Dependencies**
```sh
gem install rbnacl
```

### **2️⃣ Example `main.rb`**
```ruby
require_relative 'ed25519_fcc'
require 'base64'

# Generate Keypair
keypair = Ed25519FCC.generate_keypair
puts "Private Key (64-byte Perl format): #{Base64.strict_encode64(keypair[:private_key])}"
puts "Public Key: #{Base64.strict_encode64(keypair[:public_key])}"

# Message to sign
message = 'Hello, Ruby Ed25519!'

# Sign the message
signature = Ed25519FCC.sign_message(keypair[:private_key], message)
puts "Signature: #{Base64.strict_encode64(signature)}"

# Verify the signature
valid = Ed25519FCC.verify_signature(keypair[:public_key], message, signature)
puts "Signature Valid: #{valid}"
```

---

## **Summary**
| Feature                 | Supported |
|-------------------------|----------|
| ✅ **Ruby-native Ed25519 support (`rbnacl`)** | ✅ Yes |
| ✅ **64-byte ⇄ 32-byte Private Key Conversion** | ✅ Yes |
| ✅ **Ed25519 Keypair Generation** | ✅ Yes |
| ✅ **Message Signing** | ✅ Yes |
| ✅ **Signature Verification** | ✅ Yes |
| ✅ **Self-test Included** | ✅ Yes |

**This Ruby module is now Web3-ready for blockchain, crypto wallets, and digital signatures!**


---


# **📜 Ed25519FCC for OpenSSL**

### **📜 OpenSSL-Compatible Ed25519FCC Java Wrapper (Perl-Compatible)**
```java
package nl.factorialcoin.Ed25519FCC;

import java.security.*;
import java.security.spec.NamedParameterSpec;
import java.util.Arrays;

public class Ed25519FCC {

    // -------------------------------------------------------------------------------------------- //

    // Convert 64-byte Perl-style private key (4-bit encoding) to 32-byte seed
    private static byte[] perlToStandardPrivateKey(byte[] perlPrivateKey) {
        if (perlPrivateKey.length != 64) {
            throw new IllegalArgumentException("Invalid Perl private key length (must be 64 bytes)");
        }
        byte[] seed = new byte[32];
        for (int i = 0; i < 32; i++) {
            seed[i] = (byte) ((perlPrivateKey[2 * i] & 0x0F) | ((perlPrivateKey[2 * i + 1] & 0x0F) << 4));
        }
        return seed;
    }

    // Convert standard 32-byte private key (seed) back to Perl's 64-byte format (4-bit encoding)
    private static byte[] standardToPerlPrivateKey(byte[] seed) {
        if (seed.length != 32) {
            throw new IllegalArgumentException("Invalid standard private key length (must be 32 bytes)");
        }
        byte[] perlPrivateKey = new byte[64];
        for (int i = 0; i < 32; i++) {
            perlPrivateKey[2 * i] = (byte) ((seed[i] >> 0) & 0x0F);
            perlPrivateKey[2 * i + 1] = (byte) ((seed[i] >> 4) & 0x0F);
        }
        return perlPrivateKey;
    }

    // Convert Perl's 64-byte private key to OpenSSL's 64-byte format (seed + public key)
    private static byte[] toOpenSSLPrivateKey(byte[] perlPrivateKey, byte[] publicKey) {
        byte[] seed = perlToStandardPrivateKey(perlPrivateKey);
        byte[] opensslPrivateKey = new byte[64];

        // OpenSSL format = [32-byte seed] + [32-byte public key]
        System.arraycopy(seed, 0, opensslPrivateKey, 0, 32);
        System.arraycopy(publicKey, 0, opensslPrivateKey, 32, 32);

        return opensslPrivateKey;
    }

    // -------------------------------------------------------------------------------------------- //

    // Simple KeyPair class
    public static class KeyPairFCC {
        public final byte[] privateKey; // Perl 64-byte format
        public final byte[] publicKey;
        public KeyPairFCC(byte[] privateKey, byte[] publicKey) {
            this.privateKey = privateKey;
            this.publicKey = publicKey;
        }
    }

    // -------------------------------------------------------------------------------------------- //

    // Generate a Perl-compatible Ed25519 KeyPair (64-byte private key with 4-bit encoding)
    public static KeyPairFCC generateKeypair() throws NoSuchAlgorithmException {
        KeyPairGenerator keyGen = KeyPairGenerator.getInstance("Ed25519");
        keyGen.initialize(NamedParameterSpec.ED25519);
        KeyPair keyPair = keyGen.generateKeyPair();

        // Extract public key bytes (last 32 bytes)
        byte[] publicKey = keyPair.getPublic().getEncoded();
        publicKey = Arrays.copyOfRange(publicKey, publicKey.length - 32, publicKey.length);

        // Extract seed from private key
        byte[] seed = keyPair.getPrivate().getEncoded();
        seed = Arrays.copyOfRange(seed, seed.length - 32, seed.length);

        // Convert to Perl-style 64-byte private key
        byte[] perlPrivateKey = standardToPerlPrivateKey(seed);

        return new KeyPairFCC(perlPrivateKey, publicKey);
    }

    // Sign a message using a Perl 64-byte private key
    public static byte[] signMessage(byte[] perlPrivateKey, byte[] publicKey, byte[] message) throws NoSuchAlgorithmException, InvalidKeyException, SignatureException {
        byte[] opensslPrivateKey = toOpenSSLPrivateKey(perlPrivateKey, publicKey); // Convert to OpenSSL format

        // Create a private key from seed
        KeyFactory keyFactory = KeyFactory.getInstance("Ed25519");
        PrivateKey privKey = keyFactory.generatePrivate(new EdECPrivateKeySpec(NamedParameterSpec.ED25519, extractSeed(opensslPrivateKey)));

        // Sign the message
        Signature signer = Signature.getInstance("Ed25519");
        signer.initSign(privKey);
        signer.update(message);
        return signer.sign();
    }

    // Verify a signature using OpenSSL-style public key
    public static boolean verifySignature(byte[] publicKey, byte[] message, byte[] signature) throws NoSuchAlgorithmException, InvalidKeyException, SignatureException {
        // Create a public key object
        KeyFactory keyFactory = KeyFactory.getInstance("Ed25519");
        PublicKey pubKey = keyFactory.generatePublic(new EdECPublicKeySpec(NamedParameterSpec.ED25519, publicKey));

        // Verify the signature
        Signature verifier = Signature.getInstance("Ed25519");
        verifier.initVerify(pubKey);
        verifier.update(message);
        return verifier.verify(signature);
    }

    // Extract 32-byte seed from OpenSSL 64-byte private key
    private static byte[] extractSeed(byte[] privateKey64) {
        return Arrays.copyOfRange(privateKey64, 0, 32);
    }
}
```

### **🛠️ What This Code Does**
✅ **Perl’s 64-byte private key (4-bit encoded) is the base format** (used as input/output).  
✅ Converts **Perl private key (64 bytes) → Standard seed (32 bytes) → OpenSSL 64-byte private key (seed + public key)** dynamically before use.  
✅ Extracts public key from Perl’s keypair and **appends it to the 32-byte seed** when converting to OpenSSL format.  
✅ Uses **Java’s built-in OpenSSL-compatible Ed25519 API** for signing and verification.  
✅ **Keeps full compatibility between Perl, OpenSSL, and Android**.

### **📌 How to Use This**
#### **Generate a Perl-Compatible Keypair**
```java
KeyPairFCC keyPair = Ed25519FCC.generateKeypair();
System.out.println("Perl Private Key (64 bytes, 4-bit encoded): " + Arrays.toString(keyPair.privateKey));
System.out.println("Public Key (32 bytes): " + Arrays.toString(keyPair.publicKey));
```

#### **Sign a Message Using Perl's 64-Byte Key**
```java
byte[] signature = Ed25519FCC.signMessage(keyPair.privateKey, keyPair.publicKey, "Hello, World!".getBytes());
System.out.println("Signature: " + Arrays.toString(signature));
```

#### **Verify the Signature**
```java
boolean isValid = Ed25519FCC.verifySignature(keyPair.publicKey, "Hello, World!".getBytes(), signature);
System.out.println("Signature valid: " + isValid);
```

### **🚀 Summary**
✔ **Perl’s 64-byte private key (4-bit encoded) is the base format** and is never modified.  
✔ **Java converts it dynamically for OpenSSL function calls** (not stored permanently).  
✔ **Ensures full interoperability between Perl, OpenSSL, and Android**.  
✔ **Works natively in Java 15+ without external libraries**.  
