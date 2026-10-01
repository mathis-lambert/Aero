// Chrome's settings objects. Aero represents its password saving, which a password manager turns off to fill the
// profile's passwords itself; it fills no addresses or cards.
const setting = (read, write, clear, event) => ({
    get: method(() => call(read)),
    set: method((details) => {
        if (typeof details?.value !== "boolean") throw new Error("The value must be a boolean.");
        if (details.scope !== undefined && details.scope !== "regular") throw new Error("Only the regular scope is supported.");
        return call(write, { value: details.value });
    }),
    clear: method(() => call(clear)),
    onChange: deliveredEvent(event)
});
const fixed = (value) => ({
    get: settled({ value, levelOfControl: "not_controllable" }),
    set: method(() => { throw new Error("Aero does not let extensions change this setting."); }),
    clear: method(() => { throw new Error("Aero does not let extensions change this setting."); }),
    onChange: inertEvent()
});
define("privacy", {
    services: () => ({
        passwordSavingEnabled: setting("privacy/passwordSaving", "privacy/setPasswordSaving", "privacy/clearPasswordSaving",
                                       "privacy.services.passwordSavingEnabled.onChange"),
        autofillAddressEnabled: fixed(false),
        autofillCreditCardEnabled: fixed(false)
    })
});
