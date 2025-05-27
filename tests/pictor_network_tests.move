#[test_only]
module pictor_network::pictor_network_tests;

use pictor_network::pictor_network::{Self, GlobalData};
use sui::test_scenario::{Self, ctx};
use sui::test_utils;

// #[test]
// fun test_pictor_network() {
//     let admin = @0xAD;
//     let mut scenario = test_scenario::begin(admin);
//     {
//         pictor_network::test_init(ctx(&mut scenario));
//         test_utils::print(b"init");
//         let shared_config = test_scenario::take_shared<GlobalData>(&scenario);
//         test_scenario::return_shared<GlobalData>(shared_config);
//     };
    
    
//     // let shared = test_scenario::most_recent_id_shared<GlobalData>();
//     // shared_config.register_user(test_scenario::ctx(&mut scenario));

    

//     scenario.end();
// }
