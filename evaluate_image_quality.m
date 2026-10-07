function [b_score, n_score, p_score] = evaluate_image_quality(img)
    % EVALUATE_IMAGE_QUALITY Beräknar BRISQUE, NIQE och PIQE samt skriver ut en rapport.
    %   skriv: evaluate_image_quality(result); 
 

    b_score = brisque(img);
    n_score = niqe(img);
    p_score = piqe(img);

    % Skriv ut ormaterat
    fprintf('\n-----------------------------------------\n');
    fprintf('  Quality Metric     |    score    \n');
    fprintf('-----------------------------------------\n');
    fprintf('  BRISQUE  |  %.2f                         \n', b_score);
    fprintf('  NIQE     |  %.2f                         \n', n_score);
    fprintf('  PIQE     |  %.2f                         \n', p_score);
    fprintf('-----------------------------------------\n\n');
end