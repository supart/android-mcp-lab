export function assertDeviceId(value) {
    if (typeof value !== 'string' || !/^[a-z0-9][a-z0-9_-]{1,63}$/u.test(value)) {
        throw new Error('deviceId must use lowercase letters, digits, underscore or hyphen');
    }
}
