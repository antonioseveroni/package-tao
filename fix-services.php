<?php
// Fix missing SessionCookieService configuration
require_once __DIR__ . '/generis/common/inc.extension.php';

$serviceManager = \oat\oatbox\service\ServiceManager::getServiceManager();

// Register SessionCookieService
$sessionCookieService = new \oat\tao\model\session\SessionCookieService([
    'cookie_name' => 'tao_session',
    'cookie_lifetime' => 0,
    'cookie_path' => '/',
    'cookie_domain' => '',
    'cookie_secure' => false,
    'cookie_httponly' => true
]);

$serviceManager->register('tao/SessionCookieService', $sessionCookieService);

echo "SessionCookieService registered successfully\n";
