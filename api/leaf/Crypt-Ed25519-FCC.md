
# **🔐 Ed25519FCC: Cross-Language Ed25519 Wrapper**
A **universal cryptographic module** for **Ed25519 key management**, supporting **key generation, signing, verification**, and **Perl-compatible 64-byte ⇄ 32-byte private key conversion**.

## **📖 Table of Contents**
- [Introduction](#introduction)
- [Key Insights](#key-insights)
- [Supported Languages & Platforms](#supported-languages--platforms)
- [Key Conversion (32-byte ⇄ 64-byte)](#key-conversion-32-byte--64-byte)
- [Code Implementations](#code-implementations)
  - [Perl](#perl)
  - [Python](#python)
  - [Rust](#rust)
  - [Go](#go)
  - [Java](#java)
  - [Kotlin](#kotlin)
  - [Swift (iOS)](#swift-ios)
  - [C/C++](#cc)
  - [C/C++ Alternative](#cc-alternative)
  - [PHP](#php)
  - [Ruby](#ruby)
  - [Haskell](#haskell)
  - [Node.js (Backend)](#nodejs-backend--browser)
  - [Javascript (Browser)](#javascript-frontend)
  - [C# (.NET)](#csharp-dotnet)
  - [Elixir](#elixir)
  - [Zig](#zig)
  - [WebAssembly (WASM)](#webassembly-wasm)

---

## **Introduction**
Ed25519 is a **secure and high-performance elliptic-curve cryptographic algorithm** widely used for **digital signatures**. However, **different implementations use different private key formats**:
- ✅ **Most modern languages use a 32-byte private key** (e.g., Python, Rust, Go).
- ⚠️ **Perl (`Crypt::Ed25519`) and some C implementations use a 64-byte private key** that **requires conversion**.

This guide ensures **interoperability** between programming languages by providing:
- **Universal key conversion functions**.
- **Consistent Ed25519 keypair generation**.
- **Cross-language signing & verification**.

---

## **Key Insights**
✅ **Most modern programming languages use the standard 32-byte private key format**.  
✅ **Perl (`Crypt::Ed25519`) uses a 64-byte 4-bit encoding**, requiring **conversion to 32-byte format**.  
✅ **WebAssembly (WASM) allows browser & Web3 compatibility**.  
✅ **Older C implementations** (like `ref10` and `supercop`) store **seed + public key (64 bytes)**, where **only the first 32 bytes serve as the private key**.  
✅ **Interoperability across all platforms is possible with proper key conversions**.  
🚀 **Ed25519FCC ensures cross-platform security and flexibility** for cryptographic signing and verification in **modern applications, blockchain wallets, and Web3 ecosystems**.

---

## **Supported Languages & Platforms**
| **Language**            | **Platform**           | **Library/Module**                      | **Private Key Format** | **Key Size** | **Notes** |
|-------------------------|-----------------------|----------------------------------------|----------------------|-------------|-----------|
| **Perl**                | Server, Security      | `Crypt::Ed25519`                       | Split (4-bit)        | 64 bytes    | **Requires conversion to 32 bytes** |
| **Python**              | Server, Web3          | `pynacl`, `cryptography`               | Standard             | 32 bytes    | Compatible with most ecosystems |
| **Rust**                | Server, Web3, WASM    | `ed25519-dalek`, `ring`                | Standard             | 32 bytes    | High-performance, widely used in blockchain |
| **Go**                  | Server, CLI           | `crypto/ed25519`, `golang.org/x/crypto` | Standard             | 32 bytes    | Used in backend services |
| **Java**                | Server, Android       | `BouncyCastle`, `Tink`                 | Standard             | 32 bytes    | Common in enterprise & mobile |
| **Kotlin**              | Android, Server       | `BouncyCastle`, `Tink`                 | Standard             | 32 bytes    | Used in Android security and wallets |
| **Swift (iOS)**         | iOS/macOS             | `CryptoKit`, `BoringSSL`               | Standard             | 32 bytes    | Apple’s native Ed25519 API |
| **C/C++**               | Linux/macOS/Windows   | `libsodium`, `ed25519-donna`           | Standard             | 32 bytes    | `libsodium` recommended for security |
| **C/C++ (alt)**         | Low-level Security    | `ref10`, `supercop`                    | Seed + PubKey        | 64 bytes    | **First 32 bytes are the private key** |
| **PHP**                 | Server, Web APIs      | `sodium_crypto_sign_keypair()` (libsodium) | Standard      | 32 bytes    | Compatible with Python & Go |
| **Ruby**                | Server, CLI tools     | `RbNaCl`, `Ed25519 gem`                | Standard             | 32 bytes    | Wrapper around `libsodium` |
| **Haskell**             | Server, Research      | `Crypto.Sodium`                        | Seed + PubKey        | 64 bytes    | **First 32 bytes are the private key** |
| **Node.js (Backend)**   | Server, Web3 APIs     | `tweetnacl`, `libsodium`               | Standard             | 32 bytes    | Used in Web3 & blockchain applications |
| **JavaScript (Frontend)** | Browser (DApps)    | `tweetnacl.js`, `libsodium-wasm`       | Standard             | 32 bytes    | WebAssembly for browser compatibility |
| **TypeScript**          | Node.js, Browser      | `tweetnacl-ts`, `@noble/ed25519`       | Standard             | 32 bytes    | Modern Web3-compatible package |
| **C# (.NET)**           | Windows, Linux        | `Chaos.NaCl`, `BouncyCastle`           | Standard             | 32 bytes    | Common for enterprise security |
| **Elixir**              | Server (Erlang VM)    | `libsodium_ex`, `ed25519_ex`           | Standard             | 32 bytes    | Used in Web3 backends |
| **Zig**                 | Embedded, System Apps | `std.crypto.ed25519`                   | Standard             | 32 bytes    | High-performance cryptography |
| **WebAssembly (WASM)**  | Browser, Server       | `libsodium-wasm`, `ring`               | Standard             | 32 bytes    | Web3, DApps, lightweight cryptography |

---

## **Key Conversion (32-byte ⇄ 64-byte)**
### Convert **64-byte Perl private key** to **32-byte Standard private key** (Python)
```python
def private_key_32(perl_key_64):
    if len(perl_key_64) != 64:
        raise ValueError("Invalid Perl private key length")
    return bytes((perl_key_64[2 * i] & 0x0F) | ((perl_key_64[2 * i + 1] & 0x0F) << 4) for i in range(32))
```
### Convert **32-byte Standard private key** to **64-byte Perl private key**
```python
def private_key_64(standard_key_32):
    if len(standard_key_32) != 32:
        raise ValueError("Invalid standard private key length")
    return bytes((standard_key_32[i] >> 0) & 0x0F for i in range(32)) + bytes((standard_key_32[i] >> 4) & 0x0F for i in range(32))
```

---

## **Code Implementations**
Each language example **generates a keypair** and **prints the private & public key in hex format**.

#### **[Perl Code](#perl)**
#### **[Python Code](#python)**
#### **[Rust Code](#rust)**
#### **[Go Code](#go)**
#### **[Java Code](#java)**
#### **[Kotlin Code](#kotlin)**
#### **[Swift Code (iOS)](#swift-ios)**
#### **[C/C++ Code](#cc)**
#### **[C/C++ (Alternative) Code](#cc-alternative)**
#### **[PHP Code](#php)**
#### **[Ruby Code](#ruby)**
#### **[Haskell Code](#haskell)**
#### **[Node.js Code (Backend)](#nodejs-backend)**
#### **[JavaScript Code (Frontend)](#javascript-frontend)**
#### **[TypeScript Code](#typescript)**
#### **[C# (.NET) Code](#csharp-dotnet)**
#### **[Elixir Code](#elixir)**
#### **[Zig Code](#zig)**
#### **[WebAssembly Code (WASM)](#webassembly-wasm)**

---
<a id="perl"></a>
---

# **Ed25519FCC For Perl**
A Perl module for Ed25519 key generation, signing, and verification, supporting 64-byte ⇄ 32-byte private key conversion while ensuring full compatibility with other cryptographic libraries. Unlike other language implementations, this module operates in reverse: it works with the 32-byte standard private key externally, whereas other languages handle the 64-byte Perl private key format. Since Perl natively manages the 4-bit encoded 64-byte private key, this module converts it internally for seamless interoperability.

---

## **🔍 Features**

| Feature | Supported |
|------------------|------------------|
| **Ed25519 Keypair Generation** | ✅ Yes |
| **Message Signing** | ✅ Yes |
| **Signature Verification** | ✅ Yes |
| **64-byte Perl Private Key Internal Handling** | ✅ Yes |
| **32-byte Standard Private Key Export (Hex)** | ✅ Yes |

---

## **📌 Perl Ed25519 Module Implementation**

```perl
package Crypt::Ed25519::FCC;

use strict;
use warnings;
use Exporter 'import';
use Crypt::Ed25519;
use MIME::Base64;
use Digest::SHA qw(sha512);

our @EXPORT_OK = qw(
    generate_keypair
    sign
    verify
    private_key_32
    private_key_64
);

# Convert a 64-byte Perl private key to a 32-byte standard private key
sub private_key_32 {
    my ($privkey64) = @_;
    die "Invalid Perl private key length" unless length($privkey64) == 64;
    
    my @e;
    for my $i (0 .. 31) {
        $e[$i] = (ord(substr($privkey64, 2 * $i, 1)) & 15) | ((ord(substr($privkey64, 2 * $i + 1, 1)) & 15) << 4);
    }
    return pack("C32", @e);
}

# Convert a 32-byte standard private key to a 64-byte Perl private key
sub private_key_64 {
    my ($privkey32) = @_;
    die "Invalid standard private key length" unless length($privkey32) == 32;
    
    my @e;
    for my $i (0 .. 31) {
        $e[2 * $i] = (ord(substr($privkey32, $i, 1)) >> 0) & 15;
        $e[2 * $i + 1] = (ord(substr($privkey32, $i, 1)) >> 4) & 15;
    }
    return pack("C64", @e);
}

# Generate Ed25519 Keypair
sub generate_keypair {
    my $seed = pack("C32", map { int(rand(256)) } (1..32));
    my $privkey64 = private_key_64($seed);

    my $public_key = "\0" x 32;
    Crypt::Ed25519::generate_keypair($public_key, $privkey64, $seed);

    return (
        unpack("H*", private_key_32($privkey64)),  # Exported 32-byte private key (hex)
        unpack("H*", $public_key)                  # Public key (hex)
    );
}

# Sign a message with a Perl private key (64-byte internally)
sub sign_message {
    my ($hex_privkey, $message) = @_;
    
    my $privkey32 = pack("H*", $hex_privkey);  
    my $privkey64 = private_key_64($privkey32);

    my $signature = "\0" x 64;
    Crypt::Ed25519::sign($signature, $message, length($message), $privkey64, substr($privkey64, 32, 32));

    return unpack("H*", $signature);  # Exported as hex
}

# Verify a signature with a public key
sub verify_signature {
    my ($hex_pubkey, $message, $hex_signature) = @_;
    
    my $public_key = pack("H*", $hex_pubkey);
    my $signature = pack("H*", $hex_signature);

    return Crypt::Ed25519::verify($signature, $message, length($message), $public_key);
}

1;
```

---

## **📌 Example Usage in Perl**

```perl
use Crypt::Ed25519::FCC qw(generate_keypair sign_message verify_signature);
use strict;
use warnings;

# Generate Keypair
my ($private_key, $public_key) = generate_keypair();
print "Private Key (32-byte hex): $private_key\n";
print "Public Key (32-byte hex): $public_key\n";

# Message to sign
my $message = "Hello, FactorialCoin!";

# Sign the message
my $signature = sign_message($private_key, $message);
print "Signature (hex): $signature\n";

# Verify the signature
my $is_valid = verify_signature($public_key, $message, $signature);
print "Signature Valid: ", ($is_valid ? "Yes" : "No"), "\n";
```

---

## **📌 Installation Instructions**

### **Install Perl Ed25519 Dependencies**
```sh
cpan Crypt::Ed25519
cpan MIME::Base64
cpan Digest::SHA
```

---
<a id="python"></a>
---

# **🐍 Ed25519FCC for Python**
A Python wrapper for **Ed25519 cryptography** using **PyNaCl (libsodium bindings)**, supporting:
- ✅ **64-byte Perl ⇄ 32-byte Standard Private Key Conversion**
- ✅ **Ed25519 Keypair Generation**
- ✅ **Signing & Verification**
- ✅ **Web3-Ready for Blockchain Applications**

---

## **📜 Python Module: `ed25519_fcc.py`**
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

---

## **📌 Example Usage in Python**
```python
import base64
from ed25519_fcc import Ed25519FCC

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

---

## **📌 Installation Instructions**
1. **Install PyNaCl (Libsodium Wrapper for Python)**
   ```sh
   pip install pynacl
   ```
   
2. **Import the Module**
   ```python
   from ed25519_fcc import Ed25519FCC
   ```

---
<a id="rust"></a>
---


# **🦀 Ed25519FCC for Rust**
A **Rust implementation** of Ed25519FCC, supporting:
- ✅ **64-byte Perl ⇄ 32-byte Standard Private Key Conversion**
- ✅ **Ed25519 Keypair Generation**
- ✅ **Signing & Verification**
- ✅ **Web3-Ready for Blockchain Applications**

---

## **📜 Rust Module: `ed25519_fcc.rs`**
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

---

## **📌 Example Usage in Rust**
### **1️⃣ Add Dependencies**
Add the required library to your `Cargo.toml`:
```toml
[dependencies]
ed25519-dalek = "1.0.1"
rand = "0.8"
```

### **2️⃣ Example `main.rs`**
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

---
<a id="go"></a>
---

# **🐹 Ed25519FCC for Go**
A **Golang implementation** of Ed25519FCC, supporting:
- ✅ **64-byte Perl ⇄ 32-byte Standard Private Key Conversion**
- ✅ **Ed25519 Keypair Generation**
- ✅ **Signing & Verification**
- ✅ **Web3-Ready for Blockchain Applications**

---

## **📜 Go Module: `ed25519_fcc.go`**
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

---

## **📌 Example Usage in Go**
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

---
<a id="java"></a>
---


## **Ed25519FCC for Java (Android & Server)**
A Java wrapper for **Ed25519 cryptography**, supporting **64-byte Perl ⇄ 32-byte Standard Private Key Conversion** using **BouncyCastle**.

---

### **📌 Features**
✅ **Java & Android Compatible**
✅ **Ed25519 Keypair Generation**
✅ **Message Signing & Verification**
✅ **64-byte Perl ⇄ 32-byte Standard Private Key Conversion**
✅ **Uses BouncyCastle for cryptographic operations**

---

## **📜 Java (Android & Server)**
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

    // Simple KeyPair class
    public static class KeyPair {
        public final byte[] privateKey;
        public final byte[] publicKey;
        public KeyPair(byte[] privateKey, byte[] publicKey) {
            this.privateKey = privateKey;
            this.publicKey = publicKey;
        }
    }

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

---

## **📌 Example Usage in Java (Android & Server)**
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

---

## **📌 Installation Instructions**
- **Add BouncyCastle Dependency**:
```gradle
dependencies {
    implementation 'org.bouncycastle:bcprov-jdk15to18:1.70'
}
```

---
<a id="kotlin"></a>
---


## **Ed25519FCC for Kotlin**

A Kotlin wrapper for **Ed25519 cryptography**, supporting **64-byte Perl ⇄ 32-byte Standard Private Key Conversion**.

---

### **📌 Features**
- ✅ **Kotlin & Android Compatible**
- ✅ **Ed25519 Keypair Generation**
- ✅ **Message Signing & Verification**
- ✅ **Supports 64-byte Perl ⇄ 32-byte Standard Private Key Conversion**
- ✅ **Uses BouncyCastle for Secure Cryptography**

---

## **📜 Kotlin Code Implementation**

```kotlin
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

---

## **📌 Example Usage in Kotlin (Android)**

```kotlin
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

---

## **📦 Installation Instructions**

### **1️⃣ Add BouncyCastle Dependency to Your Android Project**
Add the following to your **`build.gradle.kts`**:

```kotlin
dependencies {
    implementation("org.bouncycastle:bcprov-jdk15to18:1.70")
}
```

### **2️⃣ Import the Module**

```kotlin
import nl.factorialcoin.Ed25519FCC.Ed25519FCC
```



---
<a id="swift-ios"></a>
---




# **📌 Ed25519FCC for Swift (iOS/macOS)**
A **Swift wrapper** for **Ed25519 cryptography** on iOS/macOS, supporting **Perl's 64-byte ⇄ 32-byte standard private key conversion**.

---

## **📌 Swift Implementation**
```swift
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

---

## **📌 Example Usage in Swift**
```swift
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

---

## **📌 Installation Instructions**
### **1️⃣ Install Libsodium for Swift**
You can install **Swift-Sodium (Libsodium bindings)** using **CocoaPods** or **Swift Package Manager (SPM)**.

### **Using CocoaPods**
1. Add the following to your `Podfile`:
   ```ruby
   pod 'Sodium', '~> 1.0'
   ```
2. Then run:
   ```sh
   pod install
   ```

---

### **Using Swift Package Manager (SPM)**
1. Open **Xcode**, go to **File** → **Swift Packages** → **Add Package Dependency**.
2. Enter:
   ```
   https://github.com/jedisct1/swift-sodium
   ```
3. Select the latest stable version and **add it to your project**.

---
<a id="cc"></a>
---


## Ed25519FCC for C/C++ (Linux/macOS/Windows)

### Overview
Ed25519FCC provides a cross-platform Ed25519 cryptographic implementation for **C and C++** using `libsodium` and `ed25519-donna`. This module enables:
- **Keypair generation** (public/private key)
- **Message signing and verification**
- **Conversion between Perl's 64-byte private key and standard 32-byte private key**
- **Compatible with modern cryptographic libraries and Web3 applications**

---

## 📌 Dependencies
To use this module, you need `libsodium` or `ed25519-donna`.

### Installing Libsodium (Recommended)
#### Linux/macOS
```sh
sudo apt install libsodium-dev  # Debian/Ubuntu
brew install libsodium         # macOS
```

#### Windows
Use **vcpkg**:
```sh
vcpkg install libsodium
```

Or download from [https://libsodium.org](https://libsodium.org).

---

## 📜 C Implementation (`ed25519_fcc.c`)

```c
#include <sodium.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define PRIVATE_KEY_SIZE 32
#define PERL_PRIVATE_KEY_SIZE 64
#define PUBLIC_KEY_SIZE 32
#define SIGNATURE_SIZE 64

// Convert 64-byte Perl private key to 32-byte standard private key
void private_key_32(uint8_t *privkey32, const uint8_t *privkey64) {
    for (int i = 0; i < PRIVATE_KEY_SIZE; i++) {
        privkey32[i] = (privkey64[2 * i] & 0x0F) | ((privkey64[2 * i + 1] & 0x0F) << 4);
    }
}

// Convert 32-byte standard private key to 64-byte Perl private key
void private_key_64(uint8_t *privkey64, const uint8_t *privkey32) {
    for (int i = 0; i < PRIVATE_KEY_SIZE; i++) {
        privkey64[2 * i] = (privkey32[i] >> 0) & 0x0F;
        privkey64[2 * i + 1] = (privkey32[i] >> 4) & 0x0F;
    }
}

// Generate Ed25519 Keypair
void generate_keypair(uint8_t *privkey64, uint8_t *pubkey) {
    uint8_t privkey32[PRIVATE_KEY_SIZE];
    crypto_sign_keypair(pubkey, privkey32);
    private_key_64(privkey64, privkey32);
}

// Sign a message using a 64-byte Perl private key
void sign_message(uint8_t *signature, const uint8_t *privkey64, const uint8_t *message, size_t message_len) {
    uint8_t privkey32[PRIVATE_KEY_SIZE];
    private_key_32(privkey32, privkey64);
    crypto_sign_detached(signature, NULL, message, message_len, privkey32);
}

// Verify a signature
int verify_signature(const uint8_t *pubkey, const uint8_t *message, size_t message_len, const uint8_t *signature) {
    return crypto_sign_verify_detached(signature, message, message_len, pubkey) == 0;
}

```

---

## 📜 C++ Wrapper (`ed25519_fcc.cpp`)

```cpp
#include <sodium.h>
#include <iostream>
#include <vector>
#include <iomanip>

class Ed25519FCC {
public:
    static std::vector<uint8_t> privateKey32(const std::vector<uint8_t>& privkey64) {
        if (privkey64.size() != 64) throw std::invalid_argument("Invalid 64-byte Perl private key length");
        std::vector<uint8_t> privkey32(32);
        for (size_t i = 0; i < 32; i++) {
            privkey32[i] = (privkey64[2 * i] & 0x0F) | ((privkey64[2 * i + 1] & 0x0F) << 4);
        }
        return privkey32;
    }

    static std::vector<uint8_t> privateKey64(const std::vector<uint8_t>& privkey32) {
        if (privkey32.size() != 32) throw std::invalid_argument("Invalid 32-byte standard private key length");
        std::vector<uint8_t> privkey64(64);
        for (size_t i = 0; i < 32; i++) {
            privkey64[2 * i] = (privkey32[i] >> 0) & 0x0F;
            privkey64[2 * i + 1] = (privkey32[i] >> 4) & 0x0F;
        }
        return privkey64;
    }

    static void generateKeypair(std::vector<uint8_t>& privkey64, std::vector<uint8_t>& pubkey) {
        std::vector<uint8_t> privkey32(32);
        pubkey.resize(32);
        crypto_sign_keypair(pubkey.data(), privkey32.data());
        privkey64 = privateKey64(privkey32);
    }

    static std::vector<uint8_t> signMessage(const std::vector<uint8_t>& privkey64, const std::vector<uint8_t>& message) {
        std::vector<uint8_t> privkey32 = privateKey32(privkey64);
        std::vector<uint8_t> signature(64);
        crypto_sign_detached(signature.data(), nullptr, message.data(), message.size(), privkey32.data());
        return signature;
    }

    static bool verifySignature(const std::vector<uint8_t>& pubkey, const std::vector<uint8_t>& message, const std::vector<uint8_t>& signature) {
        return crypto_sign_verify_detached(signature.data(), message.data(), message.size(), pubkey.data()) == 0;
    }
};

int main() {
    std::vector<uint8_t> privkey64, pubkey;
    Ed25519FCC::generateKeypair(privkey64, pubkey);
    std::cout << "Generated Keys" << std::endl;
    std::cout << "Private Key (64-byte): " << privkey64.size() << " bytes" << std::endl;
    std::cout << "Public Key: " << pubkey.size() << " bytes" << std::endl;

    std::string message = "Hello, Ed25519!";
    std::vector<uint8_t> messageBytes(message.begin(), message.end());
    std::vector<uint8_t> signature = Ed25519FCC::signMessage(privkey64, messageBytes);

    bool isValid = Ed25519FCC::verifySignature(pubkey, messageBytes, signature);
    std::cout << "Signature Valid: " << (isValid ? "Yes" : "No") << std::endl;
}
```

---
<a id="cc-alternative"></a>
---

## Ed25519FCC for C/C++ (Alternative: ref10, supercop)

### Overview
This module implements Ed25519 key generation, signing, and verification using the **ref10** and **supercop** libraries. Unlike the standard 32-byte private key format, these implementations use a **64-byte key format**, where the **first 32 bytes represent the private key (seed)** and the remaining **32 bytes store the public key**.

### Features
| Feature                 | Supported |
|-------------------------|-----------|
| ✅ **64-byte Private Key (Seed + Public Key)** | ✅ Yes |
| ✅ **Message Signing** | ✅ Yes |
| ✅ **Signature Verification** | ✅ Yes |
| ✅ **Supercop/ref10 Support** | ✅ Yes |
| ✅ **Compatible with Perl's `Crypt::Ed25519`** | ✅ Yes |

### Dependencies
- `ref10` or `supercop`
- `libsodium` (optional for compatibility)

### Installation
Ensure you have `supercop` or `ref10` compiled:
```sh
# Clone and build SUPERCOP
git clone https://github.com/floodyberry/supercop.git
cd supercop
make
```

Alternatively, install `libsodium`:
```sh
sudo apt install libsodium-dev
```

---

### C Implementation (Ed25519 with ref10/supercop)
```c
#include <sodium.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define PRIVATE_KEY_SIZE 64
#define PUBLIC_KEY_SIZE 32
#define SIGNATURE_SIZE 64

// Generate Ed25519 Keypair (64-byte private key, first 32 bytes are the seed)
void generate_keypair(uint8_t *private_key, uint8_t *public_key) {
    crypto_sign_keypair(public_key, private_key);
}

// Sign a message using a 64-byte Ed25519 private key
void sign_message(uint8_t *signature, const uint8_t *message, size_t message_len, const uint8_t *private_key) {
    crypto_sign_detached(signature, NULL, message, message_len, private_key);
}

// Verify a signature using a 32-byte Ed25519 public key
int verify_signature(const uint8_t *signature, const uint8_t *message, size_t message_len, const uint8_t *public_key) {
    return crypto_sign_verify_detached(signature, message, message_len, public_key);
}

int main() {
    uint8_t private_key[PRIVATE_KEY_SIZE];
    uint8_t public_key[PUBLIC_KEY_SIZE];
    uint8_t signature[SIGNATURE_SIZE];
    const char *message = "Hello, Ed25519!";
    size_t message_len = strlen(message);

    // Generate keypair
    generate_keypair(private_key, public_key);
    printf("Private Key (64 bytes): ");
    for (int i = 0; i < PRIVATE_KEY_SIZE; i++) printf("%02x", private_key[i]);
    printf("\n");
    printf("Public Key (32 bytes): ");
    for (int i = 0; i < PUBLIC_KEY_SIZE; i++) printf("%02x", public_key[i]);
    printf("\n");

    // Sign the message
    sign_message(signature, (const uint8_t *)message, message_len, private_key);
    printf("Signature: ");
    for (int i = 0; i < SIGNATURE_SIZE; i++) printf("%02x", signature[i]);
    printf("\n");

    // Verify the signature
    int valid = verify_signature(signature, (const uint8_t *)message, message_len, public_key);
    printf("Signature Valid: %s\n", valid == 0 ? "YES" : "NO");
    
    return 0;
}
```

---

### Compilation Instructions
```sh
gcc -o ed25519_ref10 ed25519_ref10.c -lsodium
./ed25519_ref10
```

---
<a id="php"></a>
---

# PHP Ed25519FCC Module (Libsodium)

## **📌 Overview**
This module provides Ed25519 keypair generation, message signing, signature verification, and **64-byte ⇄ 32-byte private key conversion** in PHP using **Libsodium**. It ensures **cross-platform compatibility** with **Python, Go, Rust, and JavaScript**.

## **🚀 Features**
✅ Uses **Libsodium** for Ed25519 cryptography  
✅ Supports **32-byte standard private keys** (hex export)  
✅ Provides **64-byte Perl-style key conversion** (internal use)  
✅ Fully compatible with **Python, Go, Rust, and JavaScript** implementations  

## **📜 Installation**
Ensure that your **PHP version is 7.2 or newer** and that **Libsodium** is enabled.

```sh
sudo apt-get install php-sodium # For Debian/Ubuntu
sudo dnf install php-sodium # For Fedora
```

## **📌 PHP Implementation**

```php
<?php

class Ed25519FCC {
    
    // Convert 64-byte Perl private key to 32-byte standard private key
    public static function privateKey32(string $privkey64): string {
        if (strlen($privkey64) !== 128) {
            throw new Exception("Invalid Perl private key length");
        }
        $privkey64_bin = hex2bin($privkey64);
        $privkey32_bin = '';
        for ($i = 0; $i < 32; $i++) {
            $privkey32_bin .= chr((ord($privkey64_bin[2 * $i]) & 0x0F) | ((ord($privkey64_bin[2 * $i + 1]) & 0x0F) << 4));
        }
        return bin2hex($privkey32_bin);
    }

    // Convert 32-byte standard private key to 64-byte Perl private key
    public static function privateKey64(string $privkey32): string {
        if (strlen($privkey32) !== 64) {
            throw new Exception("Invalid standard private key length");
        }
        $privkey32_bin = hex2bin($privkey32);
        $privkey64_bin = '';
        for ($i = 0; $i < 32; $i++) {
            $privkey64_bin .= chr((ord($privkey32_bin[$i]) >> 0) & 0x0F);
            $privkey64_bin .= chr((ord($privkey32_bin[$i]) >> 4) & 0x0F);
        }
        return bin2hex($privkey64_bin);
    }

    // Generate Ed25519 keypair
    public static function generateKeypair(): array {
        $keypair = sodium_crypto_sign_keypair();
        $secretKey = sodium_crypto_sign_secretkey($keypair);
        $publicKey = sodium_crypto_sign_publickey($keypair);
        return [
            'privateKey' => self::privateKey64(bin2hex(substr($secretKey, 0, 32))), // Export 64-byte Perl format
            'publicKey' => bin2hex($publicKey)
        ];
    }

    // Sign a message
    public static function signMessage(string $privkey64, string $message): string {
        $privkey32 = hex2bin(self::privateKey32($privkey64));
        return bin2hex(sodium_crypto_sign_detached($message, $privkey32));
    }

    // Verify a signature
    public static function verifySignature(string $publicKey, string $message, string $signature): bool {
        return sodium_crypto_sign_verify_detached(hex2bin($signature), $message, hex2bin($publicKey));
    }
}
```

## **📌 Example Usage**

```php
<?php
require 'Ed25519FCC.php';

// Generate Keypair
$keypair = Ed25519FCC::generateKeypair();
echo "Private Key (64-byte Perl format): " . $keypair['privateKey'] . "\n";
echo "Public Key: " . $keypair['publicKey'] . "\n";

// Message to sign
$message = "Hello, FactorialCoin!";

// Sign the message
$signature = Ed25519FCC::signMessage($keypair['privateKey'], $message);
echo "Signature: " . $signature . "\n";

// Verify the signature
$isValid = Ed25519FCC::verifySignature($keypair['publicKey'], $message, $signature);
echo "Signature Valid: " . ($isValid ? "true" : "false") . "\n";
?>
```

---
<a id="ruby"></a>
---


# **💎 Ed25519FCC for Ruby**  
A **Ruby wrapper** for Ed25519 cryptographic operations, supporting:
- ✅ **64-byte Perl ⇄ 32-byte Standard Private Key Conversion**
- ✅ **Ed25519 Keypair Generation**
- ✅ **Message Signing & Verification**
- ✅ **Secure, Web3-compatible cryptography**

---

## **📜 Ruby Module: `ed25519_fcc.rb`**
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

## **📌 Example Usage in Ruby**
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
<a id="haskell"></a>
---

# Ed25519FCC for Haskell

## 📌 Overview
Ed25519FCC is a cryptographic wrapper for Ed25519 key generation, signing, and verification in Haskell, using the `Crypto.Sodium` library. It supports **64-byte ⇄ 32-byte private key conversion**, ensuring compatibility with Perl's 64-byte format.

## 📌 Features
✅ **Haskell-native Ed25519 support (`Crypto.Sodium`)**  
✅ **64-byte ⇄ 32-byte Private Key Conversion**  
✅ **Ed25519 Keypair Generation**  
✅ **Message Signing**  
✅ **Signature Verification**  
✅ **Hex Output for Keys and Signatures**  

---

## 📦 Installation
To use Ed25519 in Haskell, install `cryptonite` and `libsodium`:

```sh
cabal update
cabal install sodium
```

For Stack users:
```sh
stack install sodium
```

Ensure `libsodium` is installed on your system:
```sh
sudo apt install libsodium-dev # Debian/Ubuntu
brew install libsodium # macOS
```

---

## 🛠 Haskell Implementation

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Ed25519FCC where

import Crypto.Sodium.Sign
import Crypto.Sodium
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8
import Data.ByteArray.Encoding (convertToBase, Base(Base16))
import Control.Monad (unless)

-- Convert 64-byte Perl private key to 32-byte standard private key
privateKey32 :: ByteString -> Either String ByteString
privateKey32 privkey64
  | BS.length privkey64 /= 64 = Left "Invalid Perl private key length"
  | otherwise = Right $ BS.pack [ (BS.index privkey64 (2 * i) .&. 0x0F) .|. ((BS.index privkey64 (2 * i + 1) .&. 0x0F) `shiftL` 4) | i <- [0..31] ]

-- Convert 32-byte standard private key to 64-byte Perl private key
privateKey64 :: ByteString -> Either String ByteString
privateKey64 privkey32
  | BS.length privkey32 /= 32 = Left "Invalid standard private key length"
  | otherwise = Right $ BS.pack (concat [[(b `shiftR` 0) .&. 0x0F, (b `shiftR` 4) .&. 0x0F] | b <- BS.unpack privkey32])

-- Generate Ed25519 Keypair
generateKeypair :: IO (ByteString, ByteString)
generateKeypair = do
  (_pk, sk) <- signKeypair
  let seed = signSecretKeyToSeed sk
  case privateKey64 seed of
    Right priv64 -> return (priv64, signPublicKeyToBytes _pk)
    Left err -> error err

-- Sign a message with a 64-byte Perl private key
signMessage :: ByteString -> ByteString -> IO ByteString
signMessage privkey64 message = do
  case privateKey32 privkey64 of
    Right priv32 -> do
      let sk = signSecretKeyFromSeed priv32
      return $ sign sk message
    Left err -> error err

-- Verify a signature with a standard Ed25519 public key
verifySignature :: ByteString -> ByteString -> ByteString -> Bool
verifySignature pubKey message signature =
  verify (signPublicKeyFromBytes pubKey) message signature

-- Convert ByteString to Hex String
hexEncode :: ByteString -> ByteString
hexEncode = convertToBase Base16
```

---

## 📝 Example Usage

```haskell
{-# LANGUAGE OverloadedStrings #-}

import Ed25519FCC
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Base16 as B16

main :: IO ()
main = do
  -- Generate Keypair
  (privKey, pubKey) <- generateKeypair
  putStrLn $ "Private Key (64-byte Perl format): " ++ C8.unpack (B16.encode privKey)
  putStrLn $ "Public Key: " ++ C8.unpack (B16.encode pubKey)

  -- Message to sign
  let message = "Hello, FactorialCoin!"

  -- Sign the message
  signature <- signMessage privKey (C8.pack message)
  putStrLn $ "Signature: " ++ C8.unpack (B16.encode signature)

  -- Verify the signature
  let isValid = verifySignature pubKey (C8.pack message) signature
  putStrLn $ "Signature Valid: " ++ show isValid
```


---
<a id="nodejs-backend"></a>
---

# **🌍 Ed25519FCC for JavaScript (Node.js & Browser)**  
A **JavaScript implementation** of `Ed25519FCC`, supporting:  
- ✅ **64-byte Perl ⇄ 32-byte Standard Private Key Conversion**  
- ✅ **Ed25519 Keypair Generation**  
- ✅ **Message Signing & Verification**  
- ✅ **Node.js & Browser Compatibility**  

Uses **TweetNaCl.js**, a fast and secure Ed25519 library.

---

## **📜 JavaScript Module: `ed25519_fcc.js`**
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

---

## **📌 Example Usage in Node.js**
### **1️⃣ Install Dependencies**
```sh
npm install tweetnacl
```

### **2️⃣ Example `main.js`**
```javascript
import Ed25519FCC from './ed25519_fcc.js';
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

---
<a id="javascript-frontend"></a>
---

## **🌐 Ed25519FCC for Browser**
The **browser version** works the same way, but uses **TweetNaCl.js** from a **CDN**.

### **📜 Browser Module: `ed25519_fcc_browser.js`**
```javascript
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
            privateKey: Ed25519FCC.privateKey64(keypair.secretKey.slice(0, 32)),
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
```

---

## **📌 Example Usage in Browser**
### **1️⃣ Include TweetNaCl.js**
```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/tweetnacl/1.0.3/nacl.min.js"></script>
<script type="module">
    import Ed25519FCC from './ed25519_fcc_browser.js';

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

---
<a id="typescript"></a>
---

# Ed25519FCC for TypeScript

## Overview
This module provides Ed25519 cryptographic operations in TypeScript, supporting both **Node.js** and **browser environments**. It includes **64-byte ⇄ 32-byte private key conversion**, ensuring compatibility with Perl's `Crypt::Ed25519` format.

## Features
- ✅ **Works in Node.js & Browsers** 🌍
- ✅ Uses **TweetNaCl.js** and **@noble/ed25519** for fast, secure cryptography.
- ✅ **64-byte ⇄ 32-byte private key conversion**.
- ✅ **Ed25519 Key Generation, Signing, and Verification**.
- ✅ **No external dependencies** other than TweetNaCl or Noble.

---

## Installation

To install the required packages, run:
```sh
npm install tweetnacl @noble/ed25519
```

---

## TypeScript Implementation

### **`Ed25519FCC.ts` (Node.js & Browser)**
```typescript
import nacl from 'tweetnacl';
import { hexToBytes, bytesToHex } from '@noble/hashes/utils';

class Ed25519FCC {
    // Convert 64-byte Perl private key to 32-byte standard private key
    static privateKey32(privkey64: Uint8Array): Uint8Array {
        if (privkey64.length !== 64) {
            throw new Error('Invalid Perl private key length');
        }
        let privkey32 = new Uint8Array(32);
        for (let i = 0; i < 32; i++) {
            privkey32[i] = (privkey64[2 * i] & 0x0F) | ((privkey64[2 * i + 1] & 0x0F) << 4);
        }
        return privkey32;
    }

    // Convert 32-byte standard private key to 64-byte Perl private key
    static privateKey64(privkey32: Uint8Array): Uint8Array {
        if (privkey32.length !== 32) {
            throw new Error('Invalid standard private key length');
        }
        let privkey64 = new Uint8Array(64);
        for (let i = 0; i < 32; i++) {
            privkey64[2 * i] = (privkey32[i] >> 0) & 0x0F;
            privkey64[2 * i + 1] = (privkey32[i] >> 4) & 0x0F;
        }
        return privkey64;
    }

    // Generate Ed25519 Keypair
    static generateKeypair(): { privateKey: string; publicKey: string } {
        const keypair = nacl.sign.keyPair();
        return {
            privateKey: bytesToHex(Ed25519FCC.privateKey64(keypair.secretKey.slice(0, 32))),
            publicKey: bytesToHex(keypair.publicKey)
        };
    }

    // Sign a message
    static signMessage(perlPrivateKey: string, message: string): string {
        const privateKey = Ed25519FCC.privateKey32(hexToBytes(perlPrivateKey));
        const signature = nacl.sign.detached(new TextEncoder().encode(message), privateKey);
        return bytesToHex(signature);
    }

    // Verify a signature
    static verifySignature(publicKey: string, message: string, signature: string): boolean {
        return nacl.sign.detached.verify(
            new TextEncoder().encode(message),
            hexToBytes(signature),
            hexToBytes(publicKey)
        );
    }
}

export default Ed25519FCC;
```

---

## Example Usage (Node.js)

Create a file `test.ts` and run:

```typescript
import Ed25519FCC from './Ed25519FCC';

// Generate Keypair
const keypair = Ed25519FCC.generateKeypair();
console.log('Private Key (64-byte Perl format):', keypair.privateKey);
console.log('Public Key:', keypair.publicKey);

// Message to sign
const message = 'Hello, FactorialCoin!';

// Sign the message
const signature = Ed25519FCC.signMessage(keypair.privateKey, message);
console.log('Signature:', signature);

// Verify the signature
const isValid = Ed25519FCC.verifySignature(keypair.publicKey, message, signature);
console.log('Signature Valid:', isValid);
```

Run the script:
```sh
ts-node test.ts
```

---

## Example Usage (Browser)

1. Load TweetNaCl.js from a CDN:
```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/tweetnacl/1.0.3/nacl.min.js"></script>
<script type="module">
    import Ed25519FCC from './Ed25519FCC.js';

    const keypair = Ed25519FCC.generateKeypair();
    console.log('Private Key (64-byte Perl format):', keypair.privateKey);
    console.log('Public Key:', keypair.publicKey);

    const message = 'Hello, FactorialCoin!';
    const signature = Ed25519FCC.signMessage(keypair.privateKey, message);

    console.log('Signature:', signature);

    const isValid = Ed25519FCC.verifySignature(keypair.publicKey, message, signature);
    console.log('Signature Valid:', isValid);
</script>
```

---
<a id="csharp-dotnet"></a>
---

# Ed25519FCC for C# (.NET)

A cross-platform **Ed25519 cryptographic module** for **C# (.NET)**, supporting key generation, signing, verification, and **64-byte ⇄ 32-byte private key conversion** for compatibility with **Perl and OpenSSL formats**.

## 📌 Features
✅ **Supports .NET Core & .NET Framework**  
✅ **Uses `Chaos.NaCl` & `BouncyCastle` for Ed25519 operations**  
✅ **Cross-compatible with Python, Go, Rust, and OpenSSL**  
✅ **64-byte (Perl format) ⇄ 32-byte (Standard format) key conversion**  
✅ **Hexadecimal output for compatibility**

---

## 📦 Dependencies

To use **Ed25519FCC** in C#, install the necessary dependencies:

```sh
# Install Chaos.NaCl (recommended)
dotnet add package Chaos.NaCl

# Optional: Install BouncyCastle for alternative cryptography
dotnet add package BouncyCastle.NetCore
```

---

## 📌 C# Implementation

```csharp
using System;
using Chaos.NaCl;
using System.Security.Cryptography;

public static class Ed25519FCC
{
    // Convert 64-byte Perl private key to 32-byte standard private key
    public static byte[] PrivateKey32(byte[] privkey64)
    {
        if (privkey64.Length != 64)
            throw new ArgumentException("Invalid 64-byte private key length");
        
        byte[] privkey32 = new byte[32];
        for (int i = 0; i < 32; i++)
            privkey32[i] = (byte)((privkey64[2 * i] & 0x0F) | ((privkey64[2 * i + 1] & 0x0F) << 4));
        
        return privkey32;
    }

    // Convert 32-byte standard private key to 64-byte Perl private key
    public static byte[] PrivateKey64(byte[] privkey32)
    {
        if (privkey32.Length != 32)
            throw new ArgumentException("Invalid 32-byte private key length");
        
        byte[] privkey64 = new byte[64];
        for (int i = 0; i < 32; i++)
        {
            privkey64[2 * i] = (byte)((privkey32[i] >> 0) & 0x0F);
            privkey64[2 * i + 1] = (byte)((privkey32[i] >> 4) & 0x0F);
        }
        return privkey64;
    }

    // Generate Ed25519 Keypair
    public static (byte[] privateKey, byte[] publicKey) GenerateKeypair()
    {
        byte[] seed = new byte[32];
        RandomNumberGenerator.Fill(seed);
        byte[] publicKey = new byte[32];
        byte[] expandedPrivateKey = new byte[64];
        Ed25519.KeyPairFromSeed(out publicKey, out expandedPrivateKey, seed);
        return (PrivateKey64(seed), publicKey);
    }

    // Sign a message using a 64-byte Perl-style private key
    public static byte[] SignMessage(byte[] privkey64, byte[] message)
    {
        byte[] privkey32 = PrivateKey32(privkey64);
        byte[] publicKey = new byte[32];
        byte[] expandedPrivateKey = new byte[64];
        Ed25519.KeyPairFromSeed(out publicKey, out expandedPrivateKey, privkey32);
        return Ed25519.Sign(message, expandedPrivateKey);
    }

    // Verify a signature using a 32-byte public key
    public static bool VerifySignature(byte[] publicKey, byte[] message, byte[] signature)
    {
        return Ed25519.Verify(signature, message, publicKey);
    }
}
```

---

## 📌 Example Usage in C#

```csharp
using System;
using System.Text;

class Program
{
    static void Main()
    {
        // Generate Keypair
        var (privateKey, publicKey) = Ed25519FCC.GenerateKeypair();
        Console.WriteLine("Private Key (64-byte Perl format): " + BitConverter.ToString(privateKey).Replace("-", ""));
        Console.WriteLine("Public Key: " + BitConverter.ToString(publicKey).Replace("-", ""));

        // Message to sign
        byte[] message = Encoding.UTF8.GetBytes("Hello, FactorialCoin!");

        // Sign the message
        byte[] signature = Ed25519FCC.SignMessage(privateKey, message);
        Console.WriteLine("Signature: " + BitConverter.ToString(signature).Replace("-", ""));

        // Verify the signature
        bool isValid = Ed25519FCC.VerifySignature(publicKey, message, signature);
        Console.WriteLine("Signature Valid: " + isValid);
    }
}
```

---
<a id="elixir"></a>
---

# **Ed25519FCC for Elixir**

A wrapper for **Ed25519 cryptography** in **Elixir** using `libsodium_ex` and `ed25519_ex`, supporting **key generation, signing, verification, and conversion between 64-byte Perl ⇄ 32-byte standard private keys**.

## **📌 Features**
✅ **Elixir & Erlang VM Compatible**  
✅ **Ed25519 Keypair Generation**  
✅ **Message Signing & Verification**  
✅ **Supports 64-byte Perl ⇄ 32-byte Standard Private Key Conversion**  
✅ **Used in Web3 & backend security applications**  

---

## **🛠️ Installation**
To use `libsodium_ex` in your Elixir project, add the dependency to `mix.exs`:

```elixir
defp deps do
  [
    {:libsodium_ex, "~> 1.0"},
    {:ed25519_ex, "~> 1.0"}
  ]
end
```

Then install dependencies:
```sh
mix deps.get
```

---

## **📜 Ed25519FCC Elixir Implementation**

```elixir
defmodule Ed25519FCC do
  @moduledoc """
  Ed25519FCC: A wrapper for Ed25519 cryptography in Elixir, supporting
  key generation, signing, verification, and 64-byte ⇄ 32-byte private key conversion.
  """
  
  alias Ed25519
  alias Libsodium.Sign

  @doc "Convert 64-byte Perl private key to 32-byte standard private key"
  def private_key_32(privkey64) when byte_size(privkey64) == 64 do
    for i <- 0..31, reduce: <<>> do
      acc ->
        <<a::4, b::4>> = :binary.part(privkey64, 2 * i, 2)
        acc <> <<(a + (b <<< 4))>>
    end
  end

  @doc "Convert 32-byte standard private key to 64-byte Perl private key"
  def private_key_64(privkey32) when byte_size(privkey32) == 32 do
    for <<byte <- privkey32>>, reduce: <<>> do
      acc ->
        acc <> <<(byte &&& 0x0F)>> <> <<(byte >>> 4)>>
    end
  end

  @doc "Generate an Ed25519 keypair (64-byte Perl-style private key)"
  def generate_keypair do
    {public_key, private_key} = Ed25519.keypair()
    {private_key_64(private_key), public_key}
  end

  @doc "Sign a message using a 64-byte Perl-style private key"
  def sign_message(private_key_64, message) do
    private_key = private_key_32(private_key_64)
    Ed25519.sign(message, private_key)
  end

  @doc "Verify a signature with a standard Ed25519 public key"
  def verify_signature(public_key, message, signature) do
    Ed25519.valid_signature?(message, signature, public_key)
  end
end
```

---

## **📌 Example Usage in Elixir**

```elixir
# Generate a new keypair
{private_key, public_key} = Ed25519FCC.generate_keypair()
IO.puts("Private Key (64-byte Perl format): #{Base.encode16(private_key)}")
IO.puts("Public Key: #{Base.encode16(public_key)}")

# Message to sign
message = "Hello, FactorialCoin!"

# Sign the message
signature = Ed25519FCC.sign_message(private_key, message)
IO.puts("Signature: #{Base.encode16(signature)}")

# Verify the signature
is_valid = Ed25519FCC.verify_signature(public_key, message, signature)
IO.puts("Signature Valid: #{is_valid}")
```

---
<a id="zig"></a>
---

# Ed25519FCC for Zig

## Overview
This document provides an Ed25519 implementation in Zig, using the standard `std.crypto.ed25519` library. It includes key generation, signing, verification, and conversion functions to ensure compatibility with systems that use the Perl 64-byte private key format.

## Features
- ✅ Uses **Zig's `std.crypto.ed25519`** for cryptographic operations
- ✅ **Keypair Generation** with 64-byte Perl compatibility
- ✅ **Message Signing & Verification**
- ✅ **64-byte ⇄ 32-byte Private Key Conversion**
- ✅ Suitable for **embedded systems & high-performance applications**

## Installation
Ensure you have Zig installed and up to date. You can install Zig from [ziglang.org](https://ziglang.org/download/).

## Implementation

### `ed25519_fcc.zig`
```zig
const std = @import("std");
const ed25519 = std.crypto.sign.Ed25519;
const Allocator = std.mem.Allocator;

pub const KeyPair = struct {
    private_key: [64]u8,
    public_key: [32]u8,
};

/// Convert 64-byte Perl private key to 32-byte standard private key
pub fn privateKey32(perl_key: [64]u8) [32]u8 {
    var standard_key: [32]u8 = undefined;
    for (0..32) |i| {
        standard_key[i] = (perl_key[2 * i] & 0x0F) | ((perl_key[2 * i + 1] & 0x0F) << 4);
    }
    return standard_key;
}

/// Convert 32-byte standard private key to 64-byte Perl private key
pub fn privateKey64(standard_key: [32]u8) [64]u8 {
    var perl_key: [64]u8 = undefined;
    for (0..32) |i| {
        perl_key[2 * i] = (standard_key[i] >> 0) & 0x0F;
        perl_key[2 * i + 1] = (standard_key[i] >> 4) & 0x0F;
    }
    return perl_key;
}

/// Generate Ed25519 keypair
pub fn generateKeypair(allocator: Allocator) !KeyPair {
    var seed: [32]u8 = undefined;
    try std.crypto.random.bytes(&seed);
    
    const keypair = try ed25519.KeyPair.create(seed, allocator);
    return KeyPair{
        .private_key = privateKey64(seed),
        .public_key = keypair.public_key.bytes,
    };
}

/// Sign a message using a 64-byte Perl private key
pub fn signMessage(private_key: [64]u8, message: []const u8, allocator: Allocator) ![64]u8 {
    const standard_key = privateKey32(private_key);
    const keypair = try ed25519.KeyPair.create(standard_key, allocator);
    return keypair.sign(message, allocator);
}

/// Verify a signature
pub fn verifySignature(public_key: [32]u8, message: []const u8, signature: [64]u8) bool {
    return ed25519.verify(signature, message, public_key);
}
```

## Example Usage

### `main.zig`
```zig
const std = @import("std");
const ed25519_fcc = @import("ed25519_fcc.zig");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;
    
    // Generate Keypair
    const keypair = try ed25519_fcc.generateKeypair(allocator);
    std.debug.print("Private Key (64-byte Perl format): {x}\n", .{keypair.private_key});
    std.debug.print("Public Key: {x}\n", .{keypair.public_key});
    
    // Message to sign
    const message = "Hello, FactorialCoin!";
    
    // Sign the message
    const signature = try ed25519_fcc.signMessage(keypair.private_key, message, allocator);
    std.debug.print("Signature: {x}\n", .{signature});
    
    // Verify the signature
    const is_valid = ed25519_fcc.verifySignature(keypair.public_key, message, signature);
    std.debug.print("Signature Valid: {}\n", .{is_valid});
}
```

## Compilation & Execution
1. Compile the program using Zig:
```sh
zig build-exe main.zig
```

2. Run the executable:
```sh
./main
```

---
<a id="webassembly-wasm"></a>
---

# Ed25519FCC for WebAssembly (WASM)

A high-performance **WebAssembly (WASM) implementation** of **Ed25519 cryptography**, supporting **key generation, signing, verification, and interoperability** with the **Perl 64-byte private key format**.

---

## 📌 Overview

- **Language:** WebAssembly (WASM)
- **Libraries:** `libsodium-wasm`, `ring`
- **Private Key Type:** Standard
- **Private Key Size:** 32 bytes
- **Use Cases:** Web3, Blockchain, DApps, Secure Browser-based Applications

✅ **Lightweight & fast** WebAssembly Ed25519 implementation
✅ **Works in Browsers and Server-side (Node.js/WebAssembly runtimes)**
✅ **Compatible with `libsodium` and `ring` for cryptographic operations**
✅ **Supports 64-byte Perl ⇄ 32-byte Standard Private Key Conversion**

---

## 📖 Installation

### **Using `libsodium-wasm`**

For **Node.js & Browsers**:

```sh
npm install libsodium-wrappers
```

For **WASM-only applications**, include it via **CDN**:

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/libsodium-wrappers/0.7.10/libsodium-wrappers.min.js"></script>
```

---

## 🚀 WebAssembly (WASM) Implementation

```javascript
import sodium from 'libsodium-wrappers';

class Ed25519FCC_WASM {

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
    static async generateKeypair() {
        await sodium.ready;
        const keypair = sodium.crypto_sign_keypair();
        return {
            privateKey: Ed25519FCC_WASM.privateKey64(keypair.privateKey.subarray(0, 32)),
            publicKey: keypair.publicKey
        };
    }

    // Sign a message with a 64-byte Perl private key
    static async signMessage(perlPrivateKey, message) {
        await sodium.ready;
        const privateKey = Ed25519FCC_WASM.privateKey32(perlPrivateKey);
        return sodium.crypto_sign_detached(message, privateKey);
    }

    // Verify a signature with a standard Ed25519 public key
    static async verifySignature(publicKey, message, signature) {
        await sodium.ready;
        return sodium.crypto_sign_verify_detached(signature, message, publicKey);
    }
}

export default Ed25519FCC_WASM;
```

---

## 📌 Example Usage in Node.js & Browser

### **1️⃣ Generate Keypair**

```javascript
import Ed25519FCC_WASM from './Ed25519FCC_WASM.js';

(async () => {
    const keypair = await Ed25519FCC_WASM.generateKeypair();
    console.log("Private Key (64-byte Perl format):", Buffer.from(keypair.privateKey).toString('hex'));
    console.log("Public Key:", Buffer.from(keypair.publicKey).toString('hex'));
})();
```

### **2️⃣ Sign & Verify Messages**

```javascript
(async () => {
    const keypair = await Ed25519FCC_WASM.generateKeypair();
    const message = new TextEncoder().encode("Hello, WebAssembly Ed25519!");

    // Sign the message
    const signature = await Ed25519FCC_WASM.signMessage(keypair.privateKey, message);
    console.log("Signature:", Buffer.from(signature).toString('hex'));

    // Verify the signature
    const isValid = await Ed25519FCC_WASM.verifySignature(keypair.publicKey, message, signature);
    console.log("Signature Valid:", isValid);
})();
```

---
---



