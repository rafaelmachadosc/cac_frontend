// Configuração da API
// Em desenvolvimento, use http://localhost:5000
// Em produção, use a URL do seu backend
const API_BASE_URL = process.env.API_BASE_URL || 
                     (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') 
                     ? 'http://localhost:5000/api' 
                     : 'https://caccoral.site/api';

const MAPS_URL = 'https://maps.app.goo.gl/h3QPY2kgzPVSxmJv8?g_st=awb';

// Exportar para uso em outros arquivos
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { API_BASE_URL, MAPS_URL };
}

