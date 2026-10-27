DROP DATABASE IF EXISTS streamteam;
CREATE DATABASE streamteam;
USE streamteam;

CREATE TABLE User (
    user_id   INT AUTO_INCREMENT,
    username  VARCHAR(63)  NOT NULL,
    email     VARCHAR(255) NOT NULL,
    password  VARCHAR(255) NOT NULL,
    PRIMARY KEY (user_id),
    UNIQUE (username),
    UNIQUE (email)
);

CREATE TABLE Artist (
    artist_id    INT AUTO_INCREMENT,
    artist_name  VARCHAR(255) NOT NULL,
    PRIMARY KEY (artist_id),
    INDEX (artist_name)
);

CREATE TABLE League (
    league_id     INT AUTO_INCREMENT,
    user_id       INT           NOT NULL,
    name          VARCHAR(255)  NOT NULL,
    roster_size   INT           NOT NULL DEFAULT 8,
    active_slots  INT           NOT NULL DEFAULT 5,
    max_teams     INT           NOT NULL DEFAULT 4,
    stream_pts    DECIMAL(12,8) NOT NULL DEFAULT 0.000001,
    single_pts    DECIMAL(10,2) NOT NULL DEFAULT 0.50,
    album_pts     DECIMAL(10,2) NOT NULL DEFAULT 3.00,
    PRIMARY KEY (league_id),
    FOREIGN KEY (user_id) REFERENCES User(user_id),
    CHECK (roster_size  > 0),
    CHECK (active_slots > 0),
    CHECK (active_slots <= roster_size),
    CHECK (max_teams    > 1)
);

CREATE TABLE Season (
    season_id   INT AUTO_INCREMENT,
    league_id   INT         NOT NULL,
    season_num  INT         NOT NULL,
    start_date  DATE        NOT NULL,
    status      VARCHAR(30) NOT NULL DEFAULT 'upcoming',
    PRIMARY KEY (season_id),
    UNIQUE (league_id, season_num),
    FOREIGN KEY (league_id) REFERENCES League(league_id),
    CHECK (season_num > 0),
    CHECK (status IN ('upcoming', 'active', 'completed'))
);

CREATE TABLE Team (
    team_id    INT AUTO_INCREMENT,
    league_id  INT          NOT NULL,
    user_id    INT          NOT NULL,
    team_name  VARCHAR(100) NOT NULL,
    PRIMARY KEY (team_id),
    UNIQUE (league_id, user_id),
    UNIQUE (league_id, team_name),
    FOREIGN KEY (league_id) REFERENCES League(league_id),
    FOREIGN KEY (user_id)   REFERENCES User(user_id)
);

CREATE TABLE ArtistRelease (
    release_id    INT AUTO_INCREMENT,
    artist_id     INT          NOT NULL,
    title         VARCHAR(200) NOT NULL,
    release_date  DATE         NOT NULL,
    release_type  VARCHAR(20)  NOT NULL,
    PRIMARY KEY (release_id),
    FOREIGN KEY (artist_id) REFERENCES Artist(artist_id),
    CHECK (release_type IN ('single', 'album'))
);

CREATE TABLE Draft (
    draft_id    INT AUTO_INCREMENT,
    season_id   INT         NOT NULL,
    draft_date  DATE        NOT NULL,
    status      VARCHAR(20) NOT NULL DEFAULT 'scheduled',
    PRIMARY KEY (draft_id),
    UNIQUE (season_id),
    FOREIGN KEY (season_id) REFERENCES Season(season_id),
    CHECK (status IN ('scheduled', 'in_progress', 'completed'))
);

CREATE TABLE DraftsIn (
    draft_id        INT NOT NULL,
    team_id         INT NOT NULL,
    draft_position  INT NOT NULL,
    PRIMARY KEY (draft_id, team_id),
    UNIQUE (draft_id, draft_position),
    FOREIGN KEY (draft_id) REFERENCES Draft(draft_id),
    FOREIGN KEY (team_id)  REFERENCES Team(team_id),
    CHECK (draft_position > 0)
);

CREATE TABLE DraftPick (
    draft_id   INT NOT NULL,
    pick_no    INT NOT NULL,
    team_id    INT NOT NULL,
    artist_id  INT NOT NULL,
    PRIMARY KEY (draft_id, pick_no),
    UNIQUE (draft_id, artist_id),               -- artists can only be picked once per draft/season
    FOREIGN KEY (draft_id)  REFERENCES Draft(draft_id),
    FOREIGN KEY (team_id)   REFERENCES Team(team_id),
    FOREIGN KEY (artist_id) REFERENCES Artist(artist_id),
    CHECK (pick_no > 0)
);

CREATE TABLE ArtistDailyStats (
    artist_id  INT             NOT NULL,
    stat_date  DATE            NOT NULL,
    streams    BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (artist_id, stat_date),
    FOREIGN KEY (artist_id) REFERENCES Artist(artist_id)
);

CREATE TABLE Matchup (
    matchup_id  INT AUTO_INCREMENT,
    season_id   INT  NOT NULL,
    team_id_a   INT  NOT NULL,
    team_id_b   INT  NOT NULL,
    start_date  DATE NOT NULL,
    PRIMARY KEY (matchup_id),
    FOREIGN KEY (season_id) REFERENCES Season(season_id),
    FOREIGN KEY (team_id_a) REFERENCES Team(team_id),
    FOREIGN KEY (team_id_b) REFERENCES Team(team_id),
    CHECK (team_id_a <> team_id_b)              -- make it so teams cant play themselves
);

CREATE TABLE Rosters (
    team_id       INT         NOT NULL,
    artist_id     INT         NOT NULL,
    acquired_at   DATETIME    NOT NULL,
    released_at   DATETIME    NULL,
    acquired_via  VARCHAR(20) NOT NULL,         -- e.g. 'draft', 'pickup'
    PRIMARY KEY (team_id, artist_id, acquired_at),
    FOREIGN KEY (team_id)   REFERENCES Team(team_id),
    FOREIGN KEY (artist_id) REFERENCES Artist(artist_id),
    CHECK (acquired_via IN ('draft', 'pickup')),
    CHECK (released_at IS NULL OR released_at > acquired_at)
);

CREATE TABLE Lineup (
    team_id         INT     NOT NULL,
    artist_id       INT     NOT NULL,
    effective_date  DATE    NOT NULL,
    is_starter      BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (team_id, artist_id, effective_date),
    FOREIGN KEY (team_id)   REFERENCES Team(team_id),
    FOREIGN KEY (artist_id) REFERENCES Artist(artist_id)
);

CREATE TABLE PickupRequest (
    request_id      INT AUTO_INCREMENT,
    team_id         INT         NOT NULL,
    add_artist_id   INT         NOT NULL,
    drop_artist_id  INT         NOT NULL,
    requested_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    PRIMARY KEY (request_id),
    FOREIGN KEY (team_id)        REFERENCES Team(team_id),
    FOREIGN KEY (add_artist_id)  REFERENCES Artist(artist_id),
    FOREIGN KEY (drop_artist_id) REFERENCES Artist(artist_id),
    CHECK (add_artist_id <> drop_artist_id),
    CHECK (status IN ('pending', 'approved', 'cancelled', 'rejected'))
);