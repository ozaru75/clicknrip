pub mod roles;

pub mod systems {
    pub mod actions;
}

pub mod models {
    pub mod config;
    pub mod game;
    pub mod player;
}

pub mod pool;

#[cfg(test)]
pub mod tests {
    pub mod utils {
        pub mod helpers;
        pub mod setup;
    }
    pub mod test_world;
}
