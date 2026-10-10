package deckers.thibault.aves;

/** Separates OEM scan compatibility from location permission and product location usage. */
final class BirdBoxScanCompatibility {
    static boolean knownAffected(String manufacturer, String model, int sdk) {
        return "HUAWEI".equalsIgnoreCase(manufacturer)
                && "MIS-AL00".equalsIgnoreCase(model) && sdk == 31;
    }

    static boolean needsLocationGuidance(boolean knownAffected, String locationService,
            boolean completedScan, long rawResultCount) {
        return "disabled".equals(locationService)
                && (knownAffected || (completedScan && rawResultCount == 0));
    }
}
