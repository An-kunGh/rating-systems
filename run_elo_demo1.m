%% run_elo_demo.m
% One-file script: load/prepare a match table -> compute Elo -> show & plot results
% - If 'matches.csv' or 'matches.xlsx' exists, it will be loaded automatically.
% - Otherwise a small sample table is created.
% - Includes a compatibility Elo function (name-first winner parsing).

%% ---------- Config ----------
useFile = "";        % "" -> auto-detect; or set "matches.csv" / "matches.xlsx"
opts = struct('K',40,'init',1500,'scale',400,'base',10,'perMatch',true);

%% ---------- Load or build table T ----------
if strlength(useFile) == 0
    if exist('matches.csv','file')
        useFile = "matches.csv";
    elseif exist('matches.xlsx','file')
        useFile = "matches.xlsx";
    end
end

if strlength(useFile) > 0
    fprintf('Reading table from %s ...\n', useFile);
    T = readtable(useFile);
else
    fprintf('No external file found. Using a small built-in sample.\n');
    % Sample: 3 players A,B,C / 9 matches
    match_id = (1:9)';
    playerA = ["A","B","A","C","B","A","C","B","A"]';
    playerB = ["B","C","C","A","A","B","B","C","C"]';
    winner  = ["A","B","A","A","B","B","C","B","C"]';
    T = table(match_id, playerA, playerB, winner);
end

% Sanity check
need = {'playerA','playerB','winner'};
missing = setdiff(need, T.Properties.VariableNames);
if ~isempty(missing)
    error('Table must contain columns: %s', strjoin(need, ', '));
end

%% ---------- Compute Elo ----------
[finalRatings, players, Rhist, order] = elo_from_table_compat(T, opts);

%% ---------- Display final ratings ----------
Result = table(players', finalRatings', 'VariableNames', {'Player','FinalElo'});
disp(Result);

%% ---------- Display per-match ratings ----------
if ~isempty(Rhist)
    RatingHistory = array2table(Rhist, 'VariableNames', players);
    RatingHistory.match_id = (1:size(Rhist,1))';
    RatingHistory = movevars(RatingHistory, 'match_id', 'Before', 1);
    disp('Ratings after each match:');
    disp(RatingHistory);
end

%% ---------- Display final ranking ----------
[sortedRatings, sortIdx] = sort(finalRatings, 'descend');
Ranking = table((1:numel(players))', players(sortIdx)', sortedRatings', ...
    'VariableNames', {'Rank','Player','Elo'});
disp('Final ranking:');
disp(Ranking);

%% ---------- Plot trajectories ----------
if ~isempty(Rhist)
    figure('Color','w'); hold on; box on;
    x = 1:size(Rhist,1);
    for j = 1:numel(players)
        plot(x, Rhist(:,j), 'LineWidth', 1.6);
    end
    xlabel('Match index (processed order)');
    ylabel('Elo rating');
    title('Elo Rating Trajectories');
    legend(players, 'Location', 'best');
end

%% ==============================================================
%% Compatibility Elo function (name-first parsing; no 'arguments' block)
function [finalRatings, players, Rhist, order] = elo_from_table_compat(T, opts)
% ELO_FROM_TABLE_COMPAT  Elo rating trajectories from a match table (name-first parsing).
% Required: T.playerA, T.playerB, T.winner
% Optional: T.match_id or T.timestamp (datetime), T.scoreA (0/0.5/1)
% opts: K(40), init(1500), scale(400), base(10), perMatch(true)

    % ---- defaults ----
    if nargin < 2, opts = struct; end
    if ~isfield(opts,'K'),        opts.K = 40; end
    if ~isfield(opts,'init'),     opts.init = 1500; end
    if ~isfield(opts,'scale'),    opts.scale = 400; end
    if ~isfield(opts,'base'),     opts.base = 10; end
    if ~isfield(opts,'perMatch'), opts.perMatch = true; end

    % ---- ordering ----
    if ismember('timestamp', T.Properties.VariableNames) && isdatetime(T.timestamp)
        [~, order] = sort(T.timestamp);
    elseif ismember('match_id', T.Properties.VariableNames)
        [~, order] = sort(T.match_id);
    else
        order = (1:height(T))';
    end
    T = T(order,:);

    % ---- names & indices ----
    pA = string(T.playerA);
    pB = string(T.playerB);
    allNames = unique([pA; pB]);
    nP = numel(allNames);
    players = cellstr(allNames)';           % return as row cellstr
    [~, idxA] = ismember(pA, allNames);
    [~, idxB] = ismember(pB, allNames);

    % ---- init ----
    R = opts.init * ones(1, nP);
    nM = height(T);
    if opts.perMatch
        Rhist = nan(nM, nP);
    else
        Rhist = [];
    end

    % ---- loop ----
    hasScoreA = ismember('scoreA', T.Properties.VariableNames);
    for k = 1:nM
        ia = idxA(k); ib = idxB(k);
        Ra = R(ia);   Rb = R(ib);

        % Expected score for A: E = 1/(1 + base^(-(Ra-Rb)/scale))
        Ea = 1 / (1 + opts.base^(-(Ra - Rb)/opts.scale));

        % Actual score for A (name-first parsing)
        if hasScoreA
            Sa = double(T.scoreA(k));
            if isnan(Sa)
                Sa = parseWinner_nameFirst(T.winner(k), pA(k), pB(k));
            end
        else
            Sa = parseWinner_nameFirst(T.winner(k), pA(k), pB(k));
        end

        % Symmetric update
        dA    = opts.K * (Sa - Ea);
        R(ia) = Ra + dA;
        R(ib) = Rb - dA;

        if opts.perMatch
            Rhist(k,:) = R;
        end
    end

    finalRatings = R;
end

function Sa = parseWinner_nameFirst(winnerEntry, nameA, nameB)
% Name-first parsing with draw support:
%  1) if winner equals playerA's name => A wins (Sa=1)
%  2) else if winner equals playerB's name => B wins (Sa=0)
%  3) else if winner == "A" => A (left) wins
%  4) else if winner == "B" => B (right) wins
%  5) else if winner == "draw" => draw (Sa=0.5)
%  6) otherwise error




    w = lower(string(winnerEntry));   % biar case-insensitive

    if w == lower(string(nameA))
        Sa = 1;                      % winner adalah nama playerA
    elseif w == lower(string(nameB))
        Sa = 0;                      % winner adalah nama playerB
    elseif w == "a"
        Sa = 1;                      % token posisi: kiri menang
    elseif w == "b"
        Sa = 0;                      % token posisi: kanan menang
    elseif w == "draw win"
        Sa = 0.6;                    % hasil seri
    elseif w == "draw lose"
        Sa = 0.4;
    elseif w == "draw"
        Sa = 0.5;
    else
        error('winner must be "A"/"B"/"draw" or a player name equal to playerA/playerB');
    end
end
