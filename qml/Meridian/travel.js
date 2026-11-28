.pragma library

// The captures and flights MeridianTravel shares across instances: one capture per travel
// key, one flight per window.

const captures = {}
const flights = new Map()

function put(key, capture) {
    captures[key] = capture
}

function peek(key) {
    return captures[key] ?? null
}

function take(key) {
    const capture = captures[key] ?? null
    delete captures[key]
    return capture
}

/// Records `traveller` as the flight on `window`, landing the previous one at once.
function fly(window, traveller) {
    const previous = flights.get(window)
    if (previous && previous !== traveller)
        previous.land()
    flights.set(window, traveller)
}

function landed(window, traveller) {
    if (flights.get(window) === traveller)
        flights.delete(window)
}

function flying() {
    return flights.size > 0
}
