package deckers.thibault.aves;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;
import java.util.zip.*;

/** Platform-independent file and checksum boundary used by the real channel. */
final class BirdBoxDiagnosticFileWriter {
    static final int MAX_JSON_BYTES = 32 * 1024 * 1024;
    static final int ZIP_THRESHOLD = 256 * 1024;
    static final long PROTECTED_AGE_MS = 24L * 60 * 60 * 1000;
    static final long MAX_CACHE_BYTES = 128L * 1024 * 1024;
    static final int MAX_CACHE_FILES = 32;
    static final class Artifact {
        final File file;
        final String mime, sha256, payloadSha256, summaryJson;
        Artifact(File file, String mime, String sha256, String payloadSha256, String summaryJson) {
            this.file = file; this.mime = mime; this.sha256 = sha256; this.payloadSha256 = payloadSha256; this.summaryJson = summaryJson;
        }
    }
    static String safeComponent(String raw) {
        final String value = raw == null ? "unknown" : raw.replaceAll("[^\\p{L}\\p{N}._-]", "_");
        final StringBuilder safe = new StringBuilder();
        value.codePoints().limit(64).forEach(safe::appendCodePoint);
        return safe.length() == 0 ? "unknown" : safe.toString();
    }
    static Artifact write(File directory, String basename, String full, String summary, String expectedPayloadSha) throws IOException {
        if (full == null || summary == null || basename == null || !basename.startsWith("BirdBox_BLE_") || !basename.equals(safeFilename(basename))) throw new IOException("invalid_file_input");
        // Check char count before materializing UTF-8. Byte limit is authoritative.
        if (full.length() > MAX_JSON_BYTES || summary.length() > 16384) throw new IOException("diagnostic_too_large");
        final byte[] fullBytes = full.getBytes(StandardCharsets.UTF_8), summaryBytes = summary.getBytes(StandardCharsets.UTF_8);
        if (fullBytes.length > MAX_JSON_BYTES || summaryBytes.length > 16384) throw new IOException("diagnostic_too_large");
        final String payloadSha = sha256(fullBytes);
        if (!payloadSha.equals(expectedPayloadSha)) throw new IOException("file_verification_failed");
        final boolean zip = fullBytes.length > ZIP_THRESHOLD;
        final byte[] output;
        if (zip) {
            final ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            try (ZipOutputStream stream = new ZipOutputStream(buffer, StandardCharsets.UTF_8)) {
                zipEntry(stream, "summary.json", summaryBytes);
                zipEntry(stream, "full_trace.json", fullBytes);
                zipEntry(stream, "README.txt", ("BirdBox BLE diagnostic snapshot\nAll locally retained records at the snapshot cutoff are in full_trace.json.\nSee retention for dropped/unknown history; a short summary is not the full trace.\nfull_trace.json SHA-256: " + payloadSha + "\nThe shared ZIP SHA-256 is shown by the App and is not embedded in itself.\n").getBytes(StandardCharsets.UTF_8));
            }
            output = buffer.toByteArray();
        } else { output = fullBytes; }
        if (!directory.isDirectory() && !directory.mkdirs()) throw new IOException("diagnostic_storage_failed");
        reserveCache(directory, output.length, System.currentTimeMillis());
        final File file = new File(directory, basename + (zip ? ".zip" : ".json"));
        if (!file.getCanonicalFile().getParentFile().equals(directory.getCanonicalFile())) throw new IOException("invalid_file_input");
        final File partial = new File(directory, file.getName() + ".partial");
        final String expected = sha256(output);
        try {
            try (FileOutputStream stream = new FileOutputStream(partial)) { stream.write(output); stream.getFD().sync(); }
            if (file.exists() || !partial.renameTo(file)) throw new IOException("diagnostic_storage_failed");
            if (!verify(file, expected)) { file.delete(); throw new IOException("file_verification_failed"); }
            return new Artifact(file, zip ? "application/zip" : "application/json", expected, payloadSha, summary);
        } finally { if (partial.exists()) partial.delete(); }
    }
    private static String safeFilename(String value) { return value.replaceAll("[^\\p{L}\\p{N}._-]", "_"); }
    private static void zipEntry(ZipOutputStream zip, String name, byte[] bytes) throws IOException {
        final ZipEntry entry = new ZipEntry(name); entry.setTime(0); zip.putNextEntry(entry); zip.write(bytes); zip.closeEntry();
    }
    static boolean verify(File file, String expected) throws IOException { return file.isFile() && sha256(file).equals(expected); }
    static String sha256(File file) throws IOException {
        final MessageDigest digest = digest();
        try (InputStream stream = new FileInputStream(file)) { byte[] buffer = new byte[16384]; int count; while ((count = stream.read(buffer)) != -1) digest.update(buffer, 0, count); }
        return hex(digest.digest());
    }
    static String sha256(byte[] bytes) { return hex(digest().digest(bytes)); }
    private static MessageDigest digest() {
        try { return MessageDigest.getInstance("SHA-256"); }
        catch (NoSuchAlgorithmException impossible) { throw new IllegalStateException(impossible); }
    }
    private static String hex(byte[] bytes) { final StringBuilder result = new StringBuilder(); for (byte b : bytes) result.append(String.format(Locale.ROOT, "%02x", b & 255)); return result.toString(); }
    static void reserveCache(File directory, long incoming, long now) throws IOException {
        final File[] files = directory.listFiles(f -> f.isFile() && f.getName().startsWith("BirdBox_BLE_") && (f.getName().endsWith(".json") || f.getName().endsWith(".zip") || f.getName().endsWith(".partial")));
        if (files == null) throw new IOException("diagnostic_storage_failed");
        Arrays.sort(files, Comparator.comparingLong(File::lastModified));
        long bytes = 0; int count = files.length;
        for (File f : files) bytes += f.length();
        for (File f : files) {
            if (now - f.lastModified() <= PROTECTED_AGE_MS) continue;
            if (count < MAX_CACHE_FILES && bytes + incoming <= MAX_CACHE_BYTES && now - f.lastModified() < 7 * PROTECTED_AGE_MS) continue;
            final long size = f.length(); if (f.delete()) { count--; bytes -= size; }
        }
        if (count >= MAX_CACHE_FILES || bytes + incoming > MAX_CACHE_BYTES) throw new IOException("diagnostic_cache_full");
    }
}
