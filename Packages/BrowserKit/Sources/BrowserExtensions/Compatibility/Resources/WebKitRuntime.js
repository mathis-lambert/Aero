    // WebKit delivers events through the `browser` and `chrome` globals. An extension may assign or redefine them,
    // as polyfills and API-hiding wrappers do; without care a replacement cuts WebKit off from the extension. So the
    // globals stay fixed accessors: a replacement, assigned or defined as a getter, is what scripts read while it
    // exposes WebKit's own runtime; otherwise, or when it throws, the native namespace is.
    {
        const nativeGlobals = new Map();
        const replacements = new Map();
        let resolving = false;
        const current = (name) => {
            const replacement = replacements.get(name);
            if (replacement && !resolving) {
                resolving = true;
                try {
                    const value = replacement.get ? replacement.get.call(globalThis) : replacement.value;
                    if (value && nativeRuntimes.has(Reflect.get(value, "runtime"))) return exposedNamespace(value);
                } catch {}
                finally { resolving = false; }
            }
            return exposedNamespace(nativeGlobals.get(name));
        };
        for (const name of ["browser", "chrome"]) {
            const descriptor = Object.getOwnPropertyDescriptor(globalThis, name);
            const value = globalThis[name];
            if (!value || !descriptor?.configurable) continue;
            nativeGlobals.set(name, value);
            Object.defineProperty(globalThis, name, {
                get: () => current(name),
                set: (replacement) => { replacements.set(name, { value: replacement }); },
                enumerable: descriptor.enumerable, configurable: false
            });
        }
        // Redefining a fixed global would throw and stop the extension's script. The definition is taken as the
        // replacement above instead.
        const defineProperty = Object.defineProperty;
        const redefines = (target, key) => target === globalThis && nativeGlobals.has(key);
        const replace = (key, descriptor) => {
            if (descriptor && "value" in descriptor) replacements.set(key, { value: descriptor.value });
            else if (typeof descriptor?.get === "function") replacements.set(key, { get: descriptor.get });
        };
        const overrides = {
            defineProperty(target, key, descriptor) {
                if (!redefines(target, key)) return defineProperty(target, key, descriptor);
                replace(key, descriptor);
                return target;
            },
            defineProperties(target, descriptors) {
                for (const key of Reflect.ownKeys(Object(descriptors))) {
                    if (redefines(target, key)) replace(key, descriptors[key]);
                    else defineProperty(target, key, descriptors[key]);
                }
                return target;
            }
        };
        defineProperty(Object, "defineProperty", { value: overrides.defineProperty, writable: true, configurable: true });
        defineProperty(Object, "defineProperties", { value: overrides.defineProperties, writable: true, configurable: true });
        const reflectDefine = Reflect.defineProperty;
        defineProperty(Reflect, "defineProperty", { writable: true, configurable: true, value(target, key, descriptor) {
            if (!redefines(target, key)) return reflectDefine(target, key, descriptor);
            replace(key, descriptor);
            return true;
        } });
        const defineGetter = Object.prototype.__defineGetter__;
        if (defineGetter) defineProperty(Object.prototype, "__defineGetter__", { writable: true, configurable: true, value(key, getter) {
            if (!redefines(this, key)) return defineGetter.call(this, key, getter);
            replace(key, { get: getter });
        } });
    }

    // WebKit has no idle callbacks, which extension pages and content scripts use to schedule work. Chrome's
    // deadline is at most 50 milliseconds; this one runs the callback as soon as the current task ends.
    if (typeof document !== "undefined" && typeof globalThis.requestIdleCallback !== "function") {
        const pending = new Map();
        let nextIdle = 0;
        globalThis.requestIdleCallback = (callback, options) => {
            if (typeof callback !== "function") throw new TypeError("The callback must be a function.");
            const id = ++nextIdle;
            pending.set(id, setTimeout(() => {
                pending.delete(id);
                const start = performance.now();
                callback({ didTimeout: false, timeRemaining: () => Math.max(0, 50 - (performance.now() - start)) });
            }, 1));
            return id;
        };
        globalThis.cancelIdleCallback = (id) => {
            clearTimeout(pending.get(id));
            pending.delete(id);
        };
    }
