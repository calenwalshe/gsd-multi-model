// Utility functions for demo project
// TODO: Add isEmpty function that checks for null, undefined, empty string, empty array, empty object

function capitalize(str) {
  if (typeof str !== 'string') return '';
  return str.charAt(0).toUpperCase() + str.slice(1);
}

module.exports = { capitalize };
