define("storage", { managed: () => ({ get: settled({}), getBytesInUse: settled(0), onChanged: inertEvent() }) });
