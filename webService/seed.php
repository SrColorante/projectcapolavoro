<?php
// Register global error/exception handlers for the seeder
set_exception_handler(function ($e) {
    header("Content-Type: application/json; charset=UTF-8");
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "error" => "Errore seeder: " . $e->getMessage()
    ]);
    exit;
});

require_once 'db.php';
header("Content-Type: application/json; charset=UTF-8");

try {
    // Check if default test users exist (by phone number ID)
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM utenti WHERE IDutente = ?");
    $stmt->execute([3391234567]);
    $count = $stmt->fetchColumn();

    if ($count == 0) {
        $stmt = $pdo->prepare("INSERT INTO utenti (IDutente, nome, cognome, nickname, email, password_hash, dataCreazione) VALUES
            (3391234567, 'Mario', 'Rossi', 'mario.rossi', 'mario.rossi@test.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', CURDATE()),
            (3391234568, 'Luca', 'Bianchi', 'luca.b', 'luca.bianchi@test.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', CURDATE()),
            (3391234569, 'Giulia', 'Verdi', 'giulia.v', 'giulia.verdi@test.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', CURDATE())");
        $stmt->execute();
        
        echo json_encode([
            "success" => true,
            "message" => "Profili di test creati con successo! Puoi accedere con numero '3391234567' e password 'password'.",
            "accounts" => [
                ["phone" => "3391234567", "password" => "password", "name" => "Mario Rossi"],
                ["phone" => "3391234568", "password" => "password", "name" => "Luca Bianchi"],
                ["phone" => "3391234569", "password" => "password", "name" => "Giulia Verdi"]
            ]
        ]);
    } else {
        echo json_encode([
            "success" => true,
            "message" => "I profili di test sono già presenti nel database. Accedi con numero '3391234567' e password 'password'.",
            "accounts" => [
                ["phone" => "3391234567", "password" => "password", "name" => "Mario Rossi"],
                ["phone" => "3391234568", "password" => "password", "name" => "Luca Bianchi"],
                ["phone" => "3391234569", "password" => "password", "name" => "Giulia Verdi"]
            ]
        ]);
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "error" => "Impossibile inserire profili di test: " . $e->getMessage()
    ]);
}
?>
