const rainbow = require('chalk-animation')
    .rainbow('Lorem ipsum dolor sit amet');

setTimeout(() => {
    rainbow.stop(); // Animation stops
}, 5000);
