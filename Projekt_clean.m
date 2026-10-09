% Struktur: 
% 1. denoising av no flash using joint bilateral filters
% 2. Specular/shadow masks
% 3. Add masks and result
% 4.Detail transfer
%% Load images
%No flash
% A = imread("./flashnoflash/puppets_01_noflash.tif");
A = imread("./flashnoflash/cave01_01_noflash.tif");
figure
imshow(A, [],'InitialMagnification', 'fit')
title("Input Image - Camera Flash off")

%Flash
% G = imread("./flashnoflash/puppets_00_flash.tif");
G = imread("./flashnoflash/cave01_00_flash.tif");
figure
imshow(G, [],'InitialMagnification', 'fit')
title("Guidance Image - Camera Flash On")

%% 0-255 till 0-1: 
flash = im2double(G);
noflash = im2double(A);

%Började testa med mindre bilderna
% flash_small = imresize(flash, 0.25);
% noflash_small = imresize(noflash, 0.25);

%använd hela bilderna OBS namnet är bara inte bytt sen!
flash_small = flash; 
noflash_small = noflash; 

figure;
imshow(flash_small , [],'InitialMagnification', 'fit')
figure;
imshow(noflash_small , [],'InitialMagnification', 'fit')
%% Denoising using joint bilateral av noflash
% no flash filtreras, men flash används som guide förkanter
sigma_s = 4.5; 
sigma_r = 0.2; %Intensitet

filtered = zeros(size(noflash_small));

radius = ceil(3*sigma_s);

[X,Y] = meshgrid(-radius:radius, -radius:radius);
spatialWeight = exp(-(X.^2 + Y.^2)/(2*sigma_s^2));

for c = 1:3

    A = noflash_small(:,:,c);
    F = flash_small(:,:,c);

    for y = 1+radius : size(A,1)-radius
        for x = 1+radius : size(A,2)-radius

            A_patch = A(y-radius:y+radius, x-radius:x+radius);
            F_patch = F(y-radius:y+radius, x-radius:x+radius);

            rangeWeight = exp(-(F_patch - F(y,x)).^2 /(2*sigma_r^2)); %Range-vikten beräknas från flash-bilden,

            weights = spatialWeight .* rangeWeight;

            weights = weights / sum(weights(:));

            filtered(y,x,c) = sum(sum(weights .* A_patch));

        end
    end
end

figure;
imshow(filtered, [],'InitialMagnification', 'fit');
title("Joint bilateral filter");

%% Shadow mask(4.3)
%Approximately linearize för shadow!
flash_linear = rgb2lin(flash_small);
ambient_linear = rgb2lin(noflash_small);

%Calculate luminance: viktad summa av RGB-kanalerna 
flash_lum = 0.2126 * flash_linear(:,:,1) + ...
            0.7152 * flash_linear(:,:,2) + ...
            0.0722 * flash_linear(:,:,3);

no_flash_lum = 0.2126 * ambient_linear(:,:,1) + ...
             0.7152 * ambient_linear(:,:,2) + ...
             0.0722 * ambient_linear(:,:,3);

%Difference map flash/no flash --------------------------------
difference_map = flash_lum - no_flash_lum;

figure;
imagesc(difference_map);
axis image;
colorbar;
title("Flash vs No-Flash Difference Map");

%Detect flash shadows--------------------------------
shadow_threshold = 0.02;
shadow_mask = difference_map <= shadow_threshold;

figure;
imshow(shadow_mask, [],'InitialMagnification', 'fit');
title("Initial Flash Shadow Mask");

%Clean the mask: morphological operations------------
se = strel('disk', 3);

shadow_mask = imopen(shadow_mask, se); %imopen removes small isolated regions/speckles
shadow_mask = imfill(shadow_mask, 'holes'); %imfill fills holes
shadow_mask = imdilate(shadow_mask, se);%imdilate expands the mask conservatively

figure;
imshow(shadow_mask, [],'InitialMagnification', 'fit');
title("Cleaned Flash Shadow Mask");

%% Specular mask
% pure flash/flash intesnsity: visualisering från icke linajriserade bilden
flash_lum_original = 0.2126 * flash_small(:,:,1) + ...
                     0.7152 * flash_small(:,:,2) + ...
                     0.0722 * flash_small(:,:,3);
figure;
imagesc(flash_lum_original);
axis image;
colorbar;
title("Pure Flash / Flash Intensity Map");
%-------------------------------------------------------------
specular_threshold = 0.95;
specular_mask = flash_lum >= specular_threshold;

%clean specular
se = strel('disk', 1);
%specular_mask = imopen(specular_mask, se); %Den kan ta bort alla
specular_mask = imfill(specular_mask, 'holes');
specular_mask = imdilate(specular_mask, se);

figure;
imshow(specular_mask,   [],'InitialMagnification', 'fit');
title("Cleaned Flash Specular Mask");

%% Combine the two masks:
M = shadow_mask | specular_mask;%pixel markeras om den tillhör antingen skuggmasken eller specularmasken.

figure;
imshow(M,   [],'InitialMagnification', 'fit');
title("Combined Flash Artifact Mask");

% Blurr the mask:Final artifact mask 
M = imgaussfilt(double(M), 1);
%instead of just 0 or 1, the mask contains values between 0 and 1 around the boundaries.

figure;
imshow(M, [],'InitialMagnification', 'fit');
title("Final Feathered Mask");

%% Detail transfer (4.2)
d = 12; %SpatialSigma (σs)
r = 0.01; 

%Ratio: describes the relative local det ail
epsilon = 0.02;

flash_base = imbilatfilt(flash_small, r, d); %utjämnad basbild
flash_detail = (flash_small + epsilon) ./ (flash_base + epsilon);

%Flash detail/quotent map:------------------------
figure;
imagesc(mean(flash_detail, 3));
axis image;
colorbar;
title("Flash Detail / Quotient Map");
%---------------------------------------------------
%Lägg på no-flash bilden: Transfer flash detail to filtered ambient image
detail_strength = 1.75;
transferred = filtered .*(1 + detail_strength * (flash_detail - 1));

% Lägg på makserna
% Ordinary bilateral-filtered no-flash image (fallback)
ambient_base = imbilatfilt(noflash_small, r, d);

%Final result
result = (1 - M) .* transferred + M .* ambient_base;
result = min(max(result, 0), 1);

figure;
imshow(result,[],'InitialMagnification', 'fit'); 
title("Flash/no-flash with detail transfer");
evaluate_image_quality(result); 

% Kvalitetsmått:-----------------------------------------------------
function [b_score, n_score, p_score] = evaluate_image_quality(img)
    % EVALUATE_IMAGE_QUALITY Beräknar BRISQUE, NIQE och PIQE samt skriver ut en rapport.
    %   skriv: evaluate_image_quality(result); 
 
    b_score = brisque(img); %statistik
    n_score = niqe(img); %hur naturlig bild ser ut
    p_score = piqe(img); %supervised, blockbaserade 

    % Skriv ut ormaterat
    fprintf('\n-----------------------------------------\n');
    fprintf('  Quality Metric     |    score    \n');
    fprintf('-----------------------------------------\n');
    fprintf('  BRISQUE  |  %.2f                         \n', b_score);
    fprintf('  NIQE     |  %.2f                         \n', n_score);
    fprintf('  PIQE     |  %.2f                         \n', p_score);
    fprintf('-----------------------------------------\n\n');
end