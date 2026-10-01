// WebKit's permissions API does not know the permissions Aero provides, such as idle. A query that names one of them
// is answered by Aero, which asks once for everything missing; the others go to WebKit.
const provided = providedPermissions;
const split = (query) => {
    const names = query?.permissions ?? [];
    const origins = query?.origins ?? [];
    if (!Array.isArray(names) || names.some(name => typeof name !== "string") ||
        !Array.isArray(origins) || origins.some(origin => typeof origin !== "string")) throw new Error("Invalid permission request.");
    const ours = names.filter((name) => provided.has(name));
    const theirs = { ...query, permissions: names.filter((name) => !provided.has(name)) };
    // What neither WebKit nor Aero can grant is refused as the person would refuse it.
    const unsupported = theirs.permissions.some(name => !nativePermissions.has(name)) ||
        origins.some(origin => /^(chrome|webkit)-extension:/i.test(origin));
    return { ours, theirs, names, origins, hasTheirs: theirs.permissions.length > 0 || origins.length > 0, unsupported };
};
for (const target of namespaces) {
    const permissions = target.permissions;
    if (!permissions) continue;
    kept.push(permissions);
    const native = Object.fromEntries(["contains", "getAll", "request", "remove"].map((name) => [name, permissions[name].bind(permissions)]));
    const replace = (name, value) => Object.defineProperty(permissions, name, { value, configurable: true });
    replace("contains", method(async (query) => {
        const { ours, theirs, hasTheirs, unsupported } = split(query);
        if (unsupported) return false;
        const granted = ours.length ? await call("permissions/provided") : [];
        return ours.every((name) => granted.includes(name)) && (!hasTheirs || await native.contains(theirs));
    }));
    replace("getAll", method(async () => {
        const all = await native.getAll();
        return { ...all, permissions: [...new Set([...(all.permissions ?? []), ...await call("permissions/provided")])] };
    }));
    replace("request", method(async (query) => {
        const { ours, theirs, names, origins, unsupported } = split(query);
        if (unsupported) return false;
        if (ours.length === 0) return await native.request(theirs);
        return await call("permissions/request", { permissions: names, origins });
    }));
    replace("remove", method(async (query) => {
        const { ours, theirs, hasTheirs, unsupported } = split(query);
        if (unsupported) return false;
        // A required permission of Aero's refuses the whole removal before WebKit gives anything up.
        if (ours.length > 0) await call("permissions/removable", { permissions: ours });
        if (hasTheirs && !await native.remove(theirs)) return false;
        return ours.length === 0 || await call("permissions/remove", { permissions: ours });
    }));
    // WebKit reports its own grants; Aero reports its own permissions through the same events. WebKit's event
    // properties cannot be replaced, so their listener methods are.
    for (const name of ["onAdded", "onRemoved"]) {
        const event = permissions[name];
        if (!event) continue;
        kept.push(event);
        const delivered = deliveredEvent(`permissions.${name}`);
        const own = Object.fromEntries(["addListener", "removeListener", "hasListener", "hasListeners"]
            .map((key) => [key, typeof event[key] === "function" ? event[key].bind(event) : () => false]));
        const methods = {
            addListener: (listener) => { own.addListener(listener); delivered.addListener(listener); },
            removeListener: (listener) => { own.removeListener(listener); delivered.removeListener(listener); },
            hasListener: (listener) => own.hasListener(listener) === true || delivered.hasListener(listener),
            hasListeners: () => own.hasListeners() === true || delivered.hasListeners()
        };
        for (const [key, value] of Object.entries(methods)) Object.defineProperty(event, key, { configurable: true, value });
    }
}
