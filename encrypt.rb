require 'ffi'
require 'openssl'
require 'base64'

# Can we just use PKCS7.encrypt?

# https://ruby-doc.org/stdlib-2.6.1/libdoc/openssl/rdoc/OpenSSL/PKCS7.html
module Encrypt
  extend FFI::Library

  ffi_lib :c
  attach_function :fopen, [:string, :string], :pointer
  attach_function :close, [:pointer], :int

  ffi_convention :stdcall
  ffi_lib :ssl
  attach_function :PEM_read_PrivateKey, [:pointer, :pointer, :pointer, :pointer], :pointer

  # EVP_PKEY_CTX *EVP_PKEY_CTX_new(EVP_PKEY *pkey, ENGINE *e);
  attach_function :EVP_PKEY_CTX_new, [:pointer, :pointer], :pointer

  # int EVP_PKEY_CTX_ctrl(EVP_PKEY_CTX *ctx, int keytype, int optype,
  #                       int cmd, int p1, void *p2);
  # attach_function :EVP_PKEY_CTX_ctl, [:pointer, :int, :int, :int, :int, :pointer], :int

  # void EVP_PKEY_CTX_free(EVP_PKEY_CTX *ctx)
  attach_function :EVP_PKEY_CTX_free, [:pointer], :void

  # int EVP_PKEY_encrypt_init(EVP_PKEY_CTX *ctx);
  attach_function :EVP_PKEY_encrypt_init, [:pointer], :int

  # int EVP_PKEY_encrypt(EVP_PKEY_CTX *ctx,
  #                      unsigned char *out, size_t *outlen,
  #                      const unsigned char *in, size_t inlen);
  attach_function :EVP_PKEY_encrypt, [:pointer, :pointer, :pointer, :pointer, :size_t], :int
end

include Encrypt

fp = fopen("spec/fixtures/ssl/signed-key.pem", "r")
pkey = PEM_read_PrivateKey(fp, FFI::Pointer::NULL, FFI::Pointer::NULL, FFI::Pointer::NULL)
ctx = EVP_PKEY_CTX_new(pkey, FFI::Pointer::NULL)
EVP_PKEY_encrypt_init(ctx)

data= "some data"
inlen = data.length
b64_encrypted = nil

FFI::MemoryPointer.new(:pointer) do |poutlen|
  EVP_PKEY_encrypt(ctx, FFI::Pointer::NULL, poutlen, data, inlen) # <= 0

  # define RSA_PKCS1_OAEP_PADDING     4
  #EVP_PKEY_CTX_set_ctl(ctx, keytype, optype, cmd, p1, p2) #rsa_padding(ctx, 4) #<= 0)

  outlen = poutlen.read(:size_t)
  FFI::MemoryPointer.new(:char, outlen) do |ptr|
    EVP_PKEY_encrypt(ctx, ptr, poutlen, data, inlen)# <= 0

    encrypted = ptr.get_string(0)
    b64_encrypted = Base64.encode64(encrypted)
    puts b64_encrypted
  end
end

#   EVP_PKEY_CTX *ctx;
#   ENGINE *eng;
#   unsigned char *out, *in;
#   size_t outlen, inlen;
#   EVP_PKEY *key;
#   /* NB: assumes eng, key, in, inlen are already set up,
#   * and that key is an RSA public key
#   */
#   ctx = EVP_PKEY_CTX_new(key,eng);
#   if (!ctx)
#     /* Error occurred */
#     if (EVP_PKEY_encrypt_init(ctx) <= 0)
#       /* Error */
#       if (EVP_PKEY_CTX_set_rsa_padding(ctx, RSA_OAEP_PADDING) <= 0)
#         /* Error */

#         /* Determine buffer length */
#         if (EVP_PKEY_encrypt(ctx, NULL, &outlen, in, inlen) <= 0)
#           /* Error */

#           out = OPENSSL_malloc(outlen);

#           if (!out)
#             /* malloc failure */

#             if (EVP_PKEY_encrypt(ctx, out, &outlen, in, inlen) <= 0)
#               /* Error */

#               /* Encrypted data is outlen bytes written to buffer out */

# #include <openssl/evp.h>
# #include <openssl/rsa.h>

# EVP_PKEY_CTX *ctx;
# unsigned char *out, *in;
# size_t outlen, inlen;
# EVP_PKEY *key;
# /* NB: assumes key in, inlen are already set up
#   * and that key is an RSA private key
#   */
# ctx = EVP_PKEY_CTX_new(key);
# if (!ctx)
#   /* Error occurred */
#   if (EVP_PKEY_decrypt_init(ctx) <= 0)
#     /* Error */
#     if (EVP_PKEY_CTX_set_rsa_padding(ctx, RSA_OAEP_PADDING) <= 0)
#       /* Error */

#       /* Determine buffer length */
#       if (EVP_PKEY_decrypt(ctx, NULL, &outlen, in, inlen) <= 0)
#         /* Error */

#         out = OPENSSL_malloc(outlen);

#         if (!out)
#           /* malloc failure */

#           if (EVP_PKEY_decrypt(ctx, out, &outlen, in, inlen) <= 0)
#             /* Error */

#             /* Decrypted data is outlen bytes written to buffer out */
